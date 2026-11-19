# 01 — cgroups v2 and pod QoS: how requests and limits become kernel limits

**Layer:** 1 Node/OS
**Date:** 2026-11-19 · **Exercise:** ⚪ not run

## 1. What it is

A pod's `resources.requests` and `resources.limits` are only numbers in the API. The kubelet and the container runtime turn them into files in the Linux cgroup v2 tree (`cpu.weight`, `cpu.max`, `memory.max`, and more), and the kernel enforces those files. The same numbers also decide the pod's **QoS class** (Guaranteed, Burstable, BestEffort), which controls where the pod sits in the cgroup tree, its `oom_score_adj`, and its order in node-pressure eviction.

Linux background (cgroup files, systemd slices) is in [Linux internals 05](../../linux-internals/05-cgroups-and-namespaces.md). This note covers only the Kubernetes mapping.

## 2. How it works at the infra layer

### QoS class is computed from the spec

| QoS class | Rule (every container in the pod) |
|---|---|
| Guaranteed | CPU and memory limits set, and requests equal limits |
| Burstable | Not Guaranteed, and at least one container has a CPU or memory request or limit |
| BestEffort | No CPU or memory requests or limits at all |

If you set only a limit, the API server copies it into the request. The class is stored in `status.qosClass` and cannot change during the pod's life.

### The cgroup tree the kubelet builds

With the systemd cgroup driver (default on OpenShift and on most current distributions):

```text
/sys/fs/cgroup/kubepods.slice/
├── kubepods-pod<uid>.slice/                  # Guaranteed pods sit directly here
│   └── crio-<container-id>.scope
├── kubepods-burstable.slice/
│   └── kubepods-burstable-pod<uid>.slice/
│       └── crio-<container-id>.scope
└── kubepods-besteffort.slice/                # cpu.weight = 1 for the whole slice
    └── kubepods-besteffort-pod<uid>.slice/
```

In the slice names the dashes in the pod UID become underscores. On containerd nodes the leaf is `cri-containerd-<id>.scope`. On kind the tree sits under an extra `kubelet.slice` prefix, so search for it with `find` (see the exercise) instead of typing a fixed path.

### Field to file mapping

| Pod spec field | cgroup v2 file | Kernel behaviour |
|---|---|---|
| `requests.cpu` | `cpu.weight` (1–10000) | Relative share of CPU time, only when CPUs are busy. Not a cap. |
| `limits.cpu` | `cpu.max` = `<quota> <period>`, e.g. `50000 100000` for 500m | Hard cap per 100 ms period. Exceeding it means **throttling** (topic 02). |
| no CPU limit | `cpu.max` = `max 100000` | No cap |
| `limits.memory` | `memory.max` | Above this the kernel reclaims, then the OOM killer runs inside the cgroup |
| no memory limit | `memory.max` = `max` | Bounded only by the parent slice and node |
| `requests.memory` | nothing by default | Used by the scheduler and for eviction ranking; written to `memory.min` / `memory.low` only with Memory QoS `TieredReservation` |

Each limit is written at the container level and summed at the pod level (`kubepods-...-pod<uid>.slice`), so the pod slice also enforces the total.

**CPU request to weight.** The kubelet still computes cgroup v1 style shares: `shares = milliCPU × 1024 / 1000`. The OCI runtime converts shares to `cpu.weight`. The old linear conversion gave a 1-CPU container a weight of about 39, much lower than the default weight of 100 that system services get. runc 1.3.2 and crun 1.23 use a new quadratic formula, so 1024 shares now maps to about 100. Same pod, different `cpu.weight` depending on the runtime version on the node. Values computed from both formulas:

| CPU request | shares | Old weight | New weight |
|---|---|---|---|
| 250m | 256 | 10 | 35 |
| 500m | 512 | 20 | 59 |
| BestEffort | 2 | 1 | 1 |

**Memory QoS.** KEP-2570 is beta and on by default in Kubernetes v1.37, but by default it writes nothing. If an admin sets `memoryThrottlingFactor`, Burstable and BestEffort containers get `memory.high` (soft throttle before `memory.max`). If an admin sets `memoryReservationPolicy: TieredReservation`, Guaranteed pod requests become `memory.min` (hard protection) and Burstable requests become `memory.low` (soft protection).

**OOM behaviour.** The kubelet sets `oom_score_adj` per container: Guaranteed `-997`, BestEffort `1000`, Burstable between 2 and 999 by the formula `1000 − 1000 × memoryRequest / nodeMemoryCapacity`. On cgroup v2 the kubelet also sets `memory.oom.group=1` (unless `singleProcessOOMKill: true`), so an OOM kills every process in the container, not one random child.

### Version facts to know (as of Nov 2026)

- Kubernetes v1.35: kubelet `failCgroupV1` defaults to `true`, so the kubelet refuses to start on a cgroup v1 node unless you override it. Full removal is tracked in KEP-5573.
- OpenShift 4.19 removed cgroup v1. A cluster still on v1 must switch to v2 (`nodes.config/cluster`, `spec.cgroupMode`) before it can upgrade.

### Commands on a node

```bash
stat -fc %T /sys/fs/cgroup                    # cgroup2fs means v2
systemd-cgls -u kubepods.slice                # tree of pod slices
cat /proc/<pid>/cgroup                        # which cgroup a process is in
cat <scope>/cpu.max <scope>/cpu.weight <scope>/memory.max
cat <scope>/memory.events                     # oom, oom_kill counters
cat /proc/<pid>/oom_score_adj
# OpenShift: oc debug node/<node> -- chroot /host <same commands>
```

## 3. Across platforms

| Kubernetes | OpenShift | HPC (Slurm) | AI training / inference |
|---|---|---|---|
| kubelet writes the pod slice, the runtime (runc/crun) writes the container scope. QoS class from requests and limits. | Same mechanism, CRI-O plus crun or runc, systemd driver, cgroup v2 only from 4.19. Node changes roll out through MachineConfig (topic 08). | `task/cgroup` plugin with `ConstrainCores` and `ConstrainRAMSpace` in `cgroup.conf` puts each job step in its own cgroup. Slurm pins cores (cpuset) instead of using CFS quota. | Training and latency-sensitive serving pods are usually Guaranteed, so they get the lowest OOM score and can use exclusive CPUs (topic 06). Data loaders are often the process that hits `memory.max`. GPU limits are a separate story: see the [AI-infra notes](../../notes/CURRICULUM.md). |

## 4. Failure modes and diagnosis

| Symptom | Cause | How to confirm | Fix |
|---|---|---|---|
| Container restarts with `OOMKilled`, exit code 137 | Usage reached `memory.max` | `kubectl describe pod` shows Last State OOMKilled; `memory.events` shows `oom_kill` rising | Raise the limit, or fix the leak. Check page cache vs anon in `memory.stat`. |
| Pod is BestEffort but the team expected protection | No requests set, or a LimitRange did not apply | `kubectl get pod -o jsonpath='{.status.qosClass}'` | Set requests; add a LimitRange with defaults (topic 10) |
| Pod is Burstable, not Guaranteed | One container (often an init or sidecar) has request ≠ limit or no limit | Check every container, including init containers | Set equal requests and limits in all containers |
| Latency spikes with low average CPU | CFS throttling from `cpu.max` | `cpu.stat` shows `nr_throttled` rising | See topic 02 |
| Same pod gets different CPU share after node upgrade | Runtime moved to the new shares-to-weight formula | Compare `cpu.weight` and `runc --version` / `crun --version` on two nodes | Expected change. Update any tool that predicts weight from the old formula. |
| kubelet fails to start after upgrade | Node still on cgroup v1 and `failCgroupV1=true` | `stat -fc %T /sys/fs/cgroup` shows `tmpfs`; kubelet log mentions cgroup v1 | Move the node OS to cgroup v2 |

## 5. Exercise

**Status:** ⚪ not run. Runs on kind (Linux host with cgroup v2, or Docker Desktop). CPU-only.

1. Create a cluster and three pods, one per QoS class.

```bash
kind create cluster --name qos
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: guaranteed}
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
    resources:
      requests: {cpu: 500m, memory: 256Mi}
      limits:   {cpu: 500m, memory: 256Mi}
---
apiVersion: v1
kind: Pod
metadata: {name: burstable}
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
    resources:
      requests: {cpu: 250m, memory: 128Mi}
      limits:   {cpu: 500m, memory: 256Mi}
---
apiVersion: v1
kind: Pod
metadata: {name: besteffort}
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF
kubectl wait --for=condition=Ready pod --all --timeout=120s
```

2. Read the QoS class and the container's own cgroup files. With cgroup v2 the container has a private cgroup namespace, so its own cgroup is mounted at `/sys/fs/cgroup`.

```bash
for p in guaranteed burstable besteffort; do
  echo "== $p $(kubectl get pod $p -o jsonpath='{.status.qosClass}')"
  kubectl exec $p -- sh -c 'echo "cpu.max:    $(cat /sys/fs/cgroup/cpu.max)";
    echo "cpu.weight: $(cat /sys/fs/cgroup/cpu.weight)";
    echo "memory.max: $(cat /sys/fs/cgroup/memory.max)";
    echo "oom_adj:    $(cat /proc/1/oom_score_adj)"'
done
```

Expected output (illustrative; `cpu.weight` depends on the runc/crun version in the kind node image, and the Burstable `oom_adj` depends on node memory, here 16 GiB):

```text
== guaranteed Guaranteed
cpu.max:    50000 100000
cpu.weight: 59
memory.max: 268435456
oom_adj:    -997
== burstable Burstable
cpu.max:    50000 100000
cpu.weight: 35
memory.max: 268435456
oom_adj:    993
== besteffort BestEffort
cpu.max:    max 100000
cpu.weight: 1
memory.max: max
oom_adj:    1000
```

With an older runtime, `cpu.weight` shows 20 and 10 instead of 59 and 35.

3. Find the pod-level slices on the node and confirm where each class sits.

```bash
for p in guaranteed burstable besteffort; do
  uid=$(kubectl get pod $p -o jsonpath='{.metadata.uid}' | tr - _)
  docker exec qos-control-plane find /sys/fs/cgroup -type d -name "*pod${uid}.slice"
done
```

Expect the Guaranteed slice directly under `kubepods.slice`, and the other two under `kubepods-burstable.slice` and `kubepods-besteffort.slice`.

4. Optional: trigger an OOM in the Guaranteed pod and read the counters.

```bash
kubectl exec guaranteed -- sh -c 'cat /sys/fs/cgroup/memory.events'
kubectl exec guaranteed -- sh -c 'head -c 400m /dev/zero | tail' || true
kubectl get pod guaranteed -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'
```

Expect `OOMKilled` and a restart count of 1.

**Evidence to capture:** the output of steps 2 and 3, `kubectl version`, and the runtime version from `docker exec qos-control-plane runc --version`. Clean up with `kind delete cluster --name qos`.

## 6. Interview angle

- **"What does a CPU request do on the node?"** It sets `cpu.weight`, a relative share used only when the CPU is busy. It is not a reservation at the kernel level; the scheduler uses it to decide placement. The limit sets `cpu.max`, a hard cap.
- **"Why does a memory request not protect my pod from the OOM killer?"** By default it is not written to any cgroup file. It affects scheduling, `oom_score_adj` for Burstable pods, and eviction ranking. Only Memory QoS `TieredReservation` turns it into `memory.min` or `memory.low`.
- **"How do you make a pod Guaranteed, and why care?"** Equal requests and limits for CPU and memory in every container. It gets the lowest OOM score, is evicted last under node pressure, and is the only class that can get exclusive CPUs from the static CPU Manager.

## Sources

- Kubernetes docs, [Pod Quality of Service classes](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/)
- Kubernetes docs, [About cgroup v2](https://kubernetes.io/docs/concepts/architecture/cgroups)
- Kubernetes blog, [New conversion from cgroup v1 CPU shares to v2 CPU weight](https://kubernetes.io/blog/2026/01/30/new-cgroup-v1-to-v2-cpu-conversion-formula/) (Jan 2026)
- Kubernetes blog, [The shift to cgroup v2 in Kubernetes](https://kubernetes.io/blog/2026/10/06/kubernetes-cgroups-v2-shift/) (Oct 2026)
- Kubernetes blog, [Kubernetes v1.37: Memory QoS graduates to beta](https://kubernetes.io/blog/2026/09/14/kubernetes-v1-37-memory-qos-graduates-to-beta/)
- [KEP-2570: Memory QoS](https://www.kubernetes.dev/resources/keps/2570/) · [KEP-5573: Remove cgroup v1 support](https://www.kubernetes.dev/resources/keps/5573/)
- Kubernetes docs, [Node-pressure eviction](https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/) (OOM score values)
- Red Hat, [OpenShift Container Platform 4.19 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html-single/release_notes) (cgroup v1 removed)
- Slurm, [cgroup.conf](https://slurm.schedmd.com/cgroup.conf.html)
