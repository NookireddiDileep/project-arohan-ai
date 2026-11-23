# 02 — CPU throttling (CFS quota) and when to drop CPU limits

**Layer:** 1 Node/OS
**Date:** 2026-11-23 · **Exercise:** ⚪ not run

## 1. What it is

A CPU limit becomes `cpu.max` in the container's cgroup (topic [01](01-cgroups-v2-pod-qos.md)). The kernel gives the cgroup a **quota** of CPU time per **period** (100 ms by default). When all threads together use the quota, the kernel stops running them until the next period starts. This pause is **throttling**. It happens even when the node has idle CPUs, so a pod can be slow while node CPU usage looks low.

Linux background is in [Linux internals 05](../../linux-internals/05-cgroups-and-namespaces.md). This note covers how to measure throttling, why it hurts multi-threaded work, and how to decide whether a workload should have a CPU limit at all.

## 2. How it works at the infra layer

### Quota, period, and per-CPU slices

- `limits.cpu: 500m` → `cpu.max` = `50000 100000`: 50 ms of CPU time in every 100 ms period.
- The quota is **summed across all threads and all CPUs**. With 4 busy threads, 50 ms is used after about 12.5 ms of wall time. The threads then wait about 87.5 ms.
- The kernel does not hand out the quota one microsecond at a time. Each CPU takes a **slice** from the global pool (`/proc/sys/kernel/sched_cfs_bandwidth_slice_us`, default 5 ms). For many-threaded, bursty programs this can let usage go slightly over quota in one period (about 1 ms per CPU at most), but the average still stays at the quota.
- Limits from the kernel documentation: period between 1 ms and 1 s; quota at least 1 ms; `max` means no cap.
- On RHEL 10 and other kernels 6.6+, the fair scheduler is **EEVDF** instead of classic CFS, but bandwidth control (`cpu.max`) works the same way. The name "CFS quota" is still used everywhere.

### The counters that prove throttling

Read `cpu.stat` in the container cgroup:

| Field | Meaning |
|---|---|
| `nr_periods` | Periods in which the cgroup had runnable threads |
| `nr_throttled` | Periods in which it hit the quota and was paused |
| `throttled_usec` | Total time the threads spent paused |
| `nr_bursts`, `burst_usec` | Use of `cpu.max.burst` (see below) |

The useful ratio is **throttled periods / periods**. Prometheus (cAdvisor) exposes the same data:

```promql
# Fraction of periods throttled, per container, over 5 minutes
sum by (namespace, pod, container) (rate(container_cpu_cfs_throttled_periods_total[5m]))
/
sum by (namespace, pod, container) (rate(container_cpu_cfs_periods_total[5m]))
```

Also check `container_cpu_cfs_throttled_seconds_total`. A ratio of 25% means the container was paused in one of every four periods. For a request-serving app this shows up directly as p99 latency.

### Why average CPU hides the problem

Monitoring often shows CPU usage per minute. A container with a 1-CPU limit that uses 0.4 CPU on average can still be throttled in many periods, because work comes in short bursts: a request fan-out, garbage collection, or a thread pool that starts 16 threads at once. The per-minute average is far below the limit. The per-100 ms usage is at the limit.

Thread pools sized from the node core count make this worse. Many runtimes (older JVMs, Go before 1.25, OpenMP, BLAS libraries) look at the host CPU count, not at `cpu.max`, and start one thread per host core. Java 10 and later, and Go 1.25 and later, read the cgroup limit; check the version you run.

### Kubelet and kernel settings

| Setting | Where | Effect |
|---|---|---|
| `cpuCFSQuota` (default `true`) | KubeletConfiguration | `false` means the kubelet never writes a quota. CPU limits are then only used for QoS class and quota objects. |
| `cpuCFSQuotaPeriod` (default `100ms`) | KubeletConfiguration | Change the period. Needs the `CustomCPUCFSQuotaPeriod` feature gate, which is still alpha and off by default. |
| `DisableCPUQuotaWithExclusiveCPUs` gate | kubelet, beta and on by default since v1.33 | With the static CPU Manager, containers that get whole, exclusive CPUs get no CFS quota. They are already limited by `cpuset`. |
| `cpu.max.burst` | cgroup v2 file | Lets a cgroup save unused quota and spend it later, up to the burst value. The Pod API has no field for it, so plain Kubernetes leaves it at 0. |

On OpenShift 4.20 and later the kubelet removes CFS quota for Guaranteed pods with whole-CPU requests on nodes with the static CPU Manager (for example through a PerformanceProfile). The older pod annotation `cpu-quota.crio.io: "disable"` now has no effect.

### When to drop CPU limits

CPU is a **compressible** resource: when CPU is busy, the kernel shares it by `cpu.weight`, which comes from the request. Nobody is killed. A limit adds a hard cap on top, even when the CPU is idle.

| Keep CPU limits | Drop CPU limits (keep requests) |
|---|---|
| Multi-tenant clusters where one team must not use idle CPU that another team paid for | Latency-sensitive services where requests are set correctly |
| A ResourceQuota requires `limits.cpu` (topic 10); then set limit well above request | Batch and HPC-style jobs that should use any idle CPU |
| You need predictable, repeatable performance (benchmarks, billing by limit) | Sidecars and agents that are throttled during short spikes |
| Guaranteed QoS is needed (limit = request), ideally with whole CPUs and the static CPU Manager (topic 06) so quota is removed | Nodes where every pod has a realistic request, so `cpu.weight` already protects each one |

The rule that works in most clusters: **always set CPU requests; set CPU limits only when you have one of the reasons in the left column.** Memory is different: memory is not compressible, so keep memory limits (topic 07).

### Commands on a node

```bash
# Find the container cgroup and read the counters
cat /proc/<pid>/cgroup
cat /sys/fs/cgroup/<path>/cpu.max /sys/fs/cgroup/<path>/cpu.stat
cat /proc/sys/kernel/sched_cfs_bandwidth_slice_us
# Kubelet settings in force
kubectl get --raw /api/v1/nodes/<node>/proxy/configz | jq '.kubeletconfig | {cpuCFSQuota, cpuCFSQuotaPeriod, cpuManagerPolicy}'
# OpenShift
oc debug node/<node> -- chroot /host cat /sys/fs/cgroup/<path>/cpu.stat
```

## 3. Across platforms

| Kubernetes | OpenShift | HPC (Slurm) | AI training / inference |
|---|---|---|---|
| `limits.cpu` → `cpu.max`. Throttling is visible in `cpu.stat` and cAdvisor metrics. Many teams set requests only. | Same mechanism. Since 4.20 the kubelet removes quota for Guaranteed whole-CPU pods with the static CPU Manager; the old CRI-O annotation is not needed. | Normally no CFS quota. `task/cgroup` with `ConstrainCores=yes` pins each job to its cores with `cpuset`, so a job cannot use more cores but is never paused inside its cores. | Data loaders, tokenizers and inference front-ends are CPU-bound. A throttled data loader leaves the accelerator waiting. Use Guaranteed pods with whole CPUs for these. Accelerator metrics are in the [AI-infra notes](../../notes/CURRICULUM.md). |

## 4. Failure modes and diagnosis

| Symptom | Cause | How to confirm | Fix |
|---|---|---|---|
| p99 latency spikes, CPU graph shows usage well below limit | Bursty work hits quota inside 100 ms periods | Throttled ratio from `cpu.stat` or PromQL above is high | Remove or raise the limit; keep the request |
| Liveness probe timeouts and restarts during start-up | JIT, class loading or cache warm-up uses many threads and is throttled | `nr_throttled` rises during start-up; probe failures in events | Raise limit, add a `startupProbe`, or remove the limit |
| App slower after moving to a bigger node | Thread pool sized from more host cores, same quota | Thread count (`ls /proc/<pid>/task \| wc -l`) vs `cpu.max` | Set thread count from the limit (`-XX:ActiveProcessorCount`, `GOMAXPROCS`, `OMP_NUM_THREADS`), or upgrade the runtime |
| Pinned pod still throttled | Static CPU Manager not active, request not a whole number, or kubelet older than v1.33 | `cpuset.cpus.effective` and `cpu.max` in the container cgroup; `cpuManagerPolicy` in configz | Guaranteed pod with integer CPU, static policy, current kubelet |
| Node CPU at 100%, one pod starves others | No limits and requests too low or missing | Compare requests with usage; BestEffort pods get `cpu.weight` 1 | Set realistic requests; add LimitRange defaults (topic 10) |
| Throttling alert fires for idle pods | Ratio computed over very few periods | Look at `nr_periods` rate, not only the ratio | Add a minimum-periods condition to the alert |

## 5. Exercise

**Status:** ⚪ not run. Runs on kind (Linux host with cgroup v2, or Docker Desktop) with at least 2 CPUs. CPU-only.

1. Create a cluster and two pods that run 4 busy threads each. One has a CPU limit, one has only a request.

```bash
kind create cluster --name throttle
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: limited}
spec:
  containers:
  - name: burn
    image: busybox:1.36
    command: ["sh", "-c", "for i in 1 2 3 4; do (while :; do :; done) & done; wait"]
    resources:
      requests: {cpu: 250m, memory: 32Mi}
      limits:   {cpu: 500m, memory: 32Mi}
---
apiVersion: v1
kind: Pod
metadata: {name: unlimited}
spec:
  containers:
  - name: burn
    image: busybox:1.36
    command: ["sh", "-c", "for i in 1 2 3 4; do (while :; do :; done) & done; wait"]
    resources:
      requests: {cpu: 250m, memory: 32Mi}
      limits:   {memory: 32Mi}
EOF
kubectl wait --for=condition=Ready pod --all --timeout=120s
```

2. Read `cpu.max` and take two samples of `cpu.stat`, 10 seconds apart.

```bash
for p in limited unlimited; do
  echo "== $p"
  kubectl exec $p -- cat /sys/fs/cgroup/cpu.max
  kubectl exec $p -- grep -E 'nr_periods|nr_throttled|throttled_usec' /sys/fs/cgroup/cpu.stat
  sleep 10
  kubectl exec $p -- grep -E 'nr_periods|nr_throttled|throttled_usec' /sys/fs/cgroup/cpu.stat
done
```

Expected output (illustrative; exact numbers depend on host CPUs and timing):

```text
== limited
50000 100000
nr_periods 412
nr_throttled 411
throttled_usec 141820000
nr_periods 512
nr_throttled 511
throttled_usec 176700000
== unlimited
max 100000
nr_periods 0
nr_throttled 0
throttled_usec 0
nr_periods 0
nr_throttled 0
throttled_usec 0
```

What to read from it: for `limited`, about 100 new periods in 10 s and almost all of them throttled, which matches the kernel note that CPU-bound limited groups are throttled nearly every period. Each period adds roughly 350 ms of paused time (4 threads × ~87 ms). For `unlimited` there is no quota, so the counters stay at 0.

3. Compare real CPU use. `kubectl top` needs metrics-server, so read `cpu.stat` `usage_usec` instead:

```bash
for p in limited unlimited; do
  a=$(kubectl exec $p -- awk '/usage_usec/{print $2}' /sys/fs/cgroup/cpu.stat)
  sleep 10
  b=$(kubectl exec $p -- awk '/usage_usec/{print $2}' /sys/fs/cgroup/cpu.stat)
  echo "$p: $(( (b - a) / 100000 ))% of one CPU"
done
```

Expect `limited` near 50% and `unlimited` near the number of free host CPUs × 100% (up to 400%). When both pods compete for the same CPUs, their equal requests give them equal `cpu.weight`.

4. Optional: change the limit to `2` (delete and re-create the pod) and repeat step 2. Throttled periods drop but do not disappear, because 4 threads still need more than 2 CPUs.

**Evidence to capture:** output of steps 2 and 3, `kubectl version`, and `nproc` on the host. Clean up with `kind delete cluster --name throttle`.

## 6. Interview angle

- **"Node CPU is at 30%, but this pod is slow. Why?"** Likely CFS throttling. The quota is per 100 ms and summed over all threads, so bursty or many-threaded code hits it while the average stays low. Show `nr_throttled` / `nr_periods` from `cpu.stat` or the cAdvisor metrics.
- **"Should we set CPU limits?"** Always set CPU requests; they set placement and `cpu.weight`. Set CPU limits only for strict tenant isolation, a quota policy that requires them, or predictable benchmarks. For latency-critical pods use Guaranteed QoS with whole CPUs and the static CPU Manager, where the kubelet removes the quota.
- **"Why is memory different?"** Memory is not compressible. Without a memory limit one pod can push the node into eviction or kernel OOM, so memory limits stay.

## Sources

- Linux kernel docs, [CFS Bandwidth Control](https://kernel.org/doc/html/v6.18/scheduler/sched-bwc.html) (quota, period, slice, burst, throttling statistics)
- Linux kernel docs, [Control Group v2](https://docs.kernel.org/admin-guide/cgroup-v2.html) (`cpu.max`, `cpu.max.burst`, `cpu.stat`)
- Kubernetes docs, [Resource management for pods and containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- Kubernetes docs, [Feature gates](https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/) (`CustomCPUCFSQuotaPeriod`, `DisableCPUQuotaWithExclusiveCPUs`)
- Kubernetes docs, [Kubelet configuration (v1beta1)](https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/) (`cpuCFSQuota`, `cpuCFSQuotaPeriod`)
- Kubernetes docs, [Control CPU management policies on the node](https://kubernetes.io/docs/tasks/administer-cluster/cpu-management-policies/)
- Red Hat, [OpenShift 4.21: Provisioning real-time and low latency workloads](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/scalability_and_performance/cnf-provisioning-low-latency-workloads) (CPU quota removed automatically since 4.20)
- Slurm, [cgroup.conf](https://slurm.schedmd.com/cgroup.conf.html) (`ConstrainCores`)
