# Kubernetes Scheduling, From kube-scheduler to GPU Gangs

> **Project AROHAN AI · Engineering notes · GPU Scheduling track**
> My notes, written after reading a LinkedIn post (Nov 2026) by an NVIDIA solutions architect on how pod scheduling works and why AI workloads need schedulers like KAI. The post gave the outline. The deeper mechanics, corrections, ops lessons and labs here are mine.
>
> Hands-on companion: [`labs/03-gpu-scheduling`](../../labs/03-gpu-scheduling/README.md)

---

## 0. TL;DR (the 10 lines to remember)

1. The scheduler **only picks a node**. It writes that choice through the `pods/binding` subresource, which sets `spec.nodeName`. The kubelet on that node does everything else.
2. Scheduling is **Filter → Score → Bind**, one pod at a time, inside a plugin framework with about a dozen extension points.
3. The scheduler looks at **requests vs node allocatable**. It never looks at real usage. Limits only matter at runtime (CPU throttling, memory OOMKill).
4. A whole GPU (`nvidia.com/gpu`) is an **integer extended resource**: no fractions, no overcommit, and requests must equal limits.
5. Sharing a GPU is a **choice you make**: time-slicing, MPS, MIG, DRA, or a scheduler-level fraction such as KAI's `gpu-fraction`. Each has a different isolation story.
6. **Taints repel, tolerations permit, affinity attracts.** GPU nodes need all three to be both protected and used.
7. **Pending** usually means no node passed filtering, but it can also mean a wrong `schedulerName`, a scheduling gate, an unbound volume, a pending preemption, or a gang waiting for its members.
8. The default scoring **spreads** pods. That's good for web apps and bad for GPUs, because it fragments free GPUs across nodes.
9. The default scheduler places **pods, not jobs**. Distributed training needs all-or-nothing (**gang**) placement, or partial jobs deadlock the cluster.
10. AI schedulers (KAI, Volcano, Kueue + coscheduling, and now upstream's alpha Workload API) add **gangs, queues, fair-share, bin-packing and topology**.

---

## 1. The real path of a pod

```
kubectl apply
   │
   ▼
kube-apiserver ── authn → authz → mutating admission → schema validation → validating admission
   │                 (ResourceQuota, LimitRanger, PodSecurity, webhooks run HERE)
   ▼
etcd  (pod stored with spec.nodeName = "")
   │
   ▼  watch
kube-scheduler ── scheduling queue → Filter → Score → Reserve → Permit → PreBind → Bind
   │                                                                 (POST pods/<name>/binding)
   ▼
etcd  (spec.nodeName = worker-2)
   │
   ▼  watch (field selector spec.nodeName=worker-2)
kubelet on worker-2 ── admit (resources, device plugin) → CRI: pull image → create sandbox → CNI → start containers
```

Things the simple version hides:

| Detail | Why it matters in ops |
|---|---|
| **Admission runs before the scheduler.** | If a `ResourceQuota` blocks a pod, the pod is **never created**. You won't find a Pending pod. You'll find a `FailedCreate` event on the ReplicaSet or Job. People debug the scheduler for a problem that is actually in admission. |
| **Binding is a subresource call.** | The scheduler `POST`s a `Binding` object, and the API server sets `spec.nodeName`. Any client with that permission can "schedule". |
| **`spec.nodeName` set at creation skips the scheduler entirely.** | The kubelet just runs it. That means no filtering, no taint checks and no resource fit. The kubelet still does its own admission, so the pod can fail with `OutOfcpu` or `OutOfmemory` instead of sitting in Pending. (Lab 03, Exercise 1.) |
| **`schedulerName` decides who owns the pod.** | If no scheduler with that name is running, the pod stays Pending **with no events at all**. No events is itself a diagnosis. |
| **The kubelet has its own admission.** | Device-plugin allocation, topology manager, and node pressure checks happen on the node. "Scheduled but failed to start" is a kubelet problem, not a scheduler problem. |

---

## 2. Inside kube-scheduler: the scheduling framework

### 2.1 Queues

The scheduler keeps three internal queues:

- **activeQ**: pods ready to be tried, ordered by the `QueueSort` plugin (default: priority, then creation time).
- **backoffQ**: pods that just failed, waiting out an exponential backoff.
- **unschedulable pods**: pods that failed and are parked until **a cluster event that could help** happens, such as a node added, a pod deleted, or a taint removed. Newer releases use **QueueingHints** so a pod is only re-queued by events that could actually change its result.

**Insight:** a Pending pod is not retried in a tight loop. If nothing in the cluster changes, it waits. Deleting another pod or adding a node is what wakes it up.

### 2.2 Extension points (one pod's journey)

```
Scheduling cycle (serial, one pod at a time)            Binding cycle (async, in parallel)
─────────────────────────────────────────────           ─────────────────────────────────
PreEnqueue  → is the pod allowed into activeQ?          PreBind  → e.g. bind PVs, DRA allocation
              (schedulingGates live here)               Bind     → POST the Binding
QueueSort                                               PostBind → cleanup / informational
PreFilter   → precompute; can reject early
Filter      → per node: can it run here?  ── none pass? → PostFilter (preemption)
PreScore
Score       → per node: 0–100 per plugin
NormalizeScore → × plugin weight → sum
Reserve     → assume resources are taken (in cache)
Permit      → approve / deny / WAIT  ← gang schedulers hold pods here
```

**Insight:** `Permit` with "wait" is how the *coscheduling* plugin and the upstream gang implementation hold pods until the whole group can be placed. It is the hook that makes all-or-nothing possible inside a pod-by-pod scheduler.

### 2.3 Filtering: "can this node run it?"

Main default filter plugins:

| Plugin | Rejects the node when… | Event text you'll see |
|---|---|---|
| `NodeResourcesFit` | requests > (allocatable − already requested) | `Insufficient cpu` / `Insufficient nvidia.com/gpu` |
| `NodeAffinity` | `nodeSelector` / required node affinity doesn't match | `didn't match Pod's node affinity/selector` |
| `TaintToleration` | a `NoSchedule`/`NoExecute` taint isn't tolerated | `had untolerated taint {nvidia.com/gpu: …}` |
| `NodeUnschedulable` | node is cordoned | `node(s) were unschedulable` |
| `NodePorts` | hostPort already in use | `didn't have free ports` |
| `VolumeBinding` / `VolumeZone` / `VolumeRestrictions` / CSI limits | volume can't attach or bind on that node or zone | `volume node affinity conflict`, `unbound immediate PersistentVolumeClaims` |
| `InterPodAffinity` | required (anti-)affinity is violated | `didn't match pod anti-affinity rules` |
| `PodTopologySpread` | `whenUnsatisfiable: DoNotSchedule` skew is exceeded | `didn't match pod topology spread constraints` |
| `DynamicResources` | DRA claim can't be satisfied | `cannot allocate all claims` |

**How to read the event.** `0/5 nodes are available: 1 Insufficient nvidia.com/gpu, 2 node(s) had untolerated taint {...}, 2 node(s) didn't match Pod's node affinity/selector.` This is a **per-node reason count**, and it is the most useful line in scheduling triage. Add up the numbers and they cover every node. Each node is listed under the first filter that rejected it.

**Big-cluster insight: `percentageOfNodesToScore`.** On large clusters the scheduler stops filtering once it has found "enough" feasible nodes. The default is adaptive: about 50% at 100 nodes, shrinking toward 5% for very large clusters. So the "best" node is the best **among a sample**. That's a deliberate trade of placement quality for throughput, and it's one reason AI schedulers do their own global optimization.

### 2.4 Scoring: "which survivor is best?"

Each score plugin returns 0–100 per node. The result is multiplied by the plugin weight and summed. Default weights (KubeSchedulerConfiguration `v1`):

| Score plugin | Default weight | What it prefers |
|---|---|---|
| `TaintToleration` | 3 | fewer `PreferNoSchedule` taints that aren't tolerated |
| `NodeAffinity` | 2 | nodes matching **preferred** affinity terms (your weights) |
| `PodTopologySpread` | 2 | lower skew. **Default system constraints spread pods of the same ReplicaSet/StatefulSet across nodes and zones even if you configured nothing.** |
| `InterPodAffinity` | 2 | preferred pod (anti-)affinity |
| `NodeResourcesFit` | 1 | default strategy **`LeastAllocated`**: the emptiest node wins. It scores **cpu and memory only** unless you add resources. |
| `NodeResourcesBalancedAllocation` | 1 | balanced cpu/memory usage ratio |
| `ImageLocality` | 1 | node already has the image (very relevant for 10+ GB AI images) |

Then the scheduler picks the highest total (ties are broken randomly) and writes one thing: the node name.

**Insight: why the defaults hurt GPU clusters.** `LeastAllocated` plus default topology spread equals **spreading**. Put four 1-GPU pods on two 4-GPU nodes and you get 2 + 2. Now a 4-GPU pod can't fit anywhere, even though the cluster has 4 free GPUs. That's **fragmentation**. The fix is bin-packing (`MostAllocated` or `RequestedToCapacityRatio`, with `nvidia.com/gpu` given a high weight), which a scheduler profile can do. (Lab 03, Exercise 5.)

```yaml
# Bin-packing profile (secondary scheduler or OpenShift-style profile)
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
profiles:
- schedulerName: binpack-scheduler
  plugins:
    score:
      disabled:
      - name: NodeResourcesBalancedAllocation
      - name: PodTopologySpread
  pluginConfig:
  - name: NodeResourcesFit
    args:
      scoringStrategy:
        type: MostAllocated
        resources:
        - {name: cpu, weight: 1}
        - {name: memory, weight: 1}
        - {name: nvidia.com/gpu, weight: 5}
```

### 2.5 PostFilter: preemption

If no node passes filtering, `DefaultPreemption` looks for a node where evicting **lower-priority** pods would make room. It:

1. sets `status.nominatedNodeName` on the pending pod,
2. evicts the victims gracefully (respecting PDBs on a best-effort basis),
3. waits for them to terminate. The pod goes back through the queue and usually lands on the nominated node.

**Insight:** a Pending pod with `nominatedNodeName` set is **not stuck**. It's waiting for victims to finish terminating. A long `terminationGracePeriodSeconds` on victims means slow preemption.

---

## 3. Requests, limits and what the scheduler actually sees

| | Requests | Limits |
|---|---|---|
| Used by the scheduler | ✅ (sum of requests vs allocatable) | ❌ |
| Enforced at runtime | CPU: cgroup `cpu.weight` (a share under contention) | CPU: CFS quota → **throttling**. Memory: **OOMKill** |
| Affects QoS class | Guaranteed (req = lim for all), Burstable, BestEffort | same |
| Eviction order under node pressure | BestEffort → Burstable (above request) → Guaranteed | |

Details that catch people out:

- **Allocatable, not capacity.** `allocatable = capacity − kube-reserved − system-reserved − eviction threshold`. Check it with `kubectl describe node | grep -A8 Allocatable`.
- **The pod's effective request** is `max(largest init container, sum of app containers + sidecars) + RuntimeClass overhead`.
- **The scheduler is blind to actual usage.** A node at 95% real CPU with low requests still looks "empty". Overcommit is a request-sizing problem, not a scheduler bug.
- **Extended resources (`nvidia.com/gpu`)** must be integers. Request must equal limit (or you set only the limit). They can't be overcommitted. `nvidia.com/gpu: 0.5` is rejected by the API server. (Lab 03, Exercise 4.)

---

## 4. GPUs in Kubernetes: how a GPU becomes schedulable

```
GPU hardware → NVIDIA driver → container toolkit (runtime hook / CDI)
            → device plugin advertises nvidia.com/gpu: N in node allocatable
            → GPU Feature Discovery labels the node (product, memory, MIG capable…)
            → (GPU Operator installs and manages all of the above, plus DCGM exporter)
```

If any layer is unhealthy, the node advertises `nvidia.com/gpu: 0`, or nothing at all, and GPU pods show `Insufficient nvidia.com/gpu`. **Check `kubectl describe node` allocatable before you blame the scheduler.**

### Sharing options (the "a GPU isn't divisible" line, expanded)

| Method | What the scheduler sees | Isolation | Good for |
|---|---|---|---|
| **Whole GPU** (default) | `nvidia.com/gpu: 1` = 1 physical GPU | full | training, big inference |
| **Time-slicing** (device plugin `replicas`) | one GPU is advertised as N "GPUs" | **none**: shared memory, no fault isolation, contexts take turns | dev and notebooks, small bursty inference |
| **MPS** | shared, with limits on compute share / memory | partial (software) | many small concurrent inference processes |
| **MIG** (A100/H100/…) | e.g. `nvidia.com/mig-1g.10gb` (mixed strategy) | **hardware**: dedicated SMs, memory and cache | multi-tenant inference with predictable latency |
| **DRA** (Dynamic Resource Allocation) | `ResourceClaim`s with device attributes | depends on the driver | the long-term direction: richer selection than an integer count |
| **Scheduler-level fractions** (KAI `gpu-fraction: "0.5"`) | KAI books part of a GPU and pins pods to the same physical device | **none by default** (`NonMemoryEnforced`). Optional enforcement modes exist (HAMi-core, NvFractions) | packing small inference/dev pods |

**Ops lesson:** "fractional GPU" without memory enforcement means one noisy pod can OOM another pod's CUDA context. Know which mode you're running.

---

## 5. Taints, tolerations and affinity, done properly for GPU nodes

```
Taint  on node:  nvidia.com/gpu=present:NoSchedule   → keeps CPU pods OFF expensive GPU nodes
Toleration on pod:                                     → ALLOWS the GPU pod onto them (doesn't pull)
Affinity / nodeSelector on pod (or a GPU request):     → PULLS the pod to the right GPU type
```

- A toleration alone lets a pod land on **any** node, CPU nodes included. That's the classic misconception. (Lab 03, Exercise 3.)
- A GPU *request* already acts like an attractor, because only GPU nodes pass `NodeResourcesFit`. You still need affinity to choose **which** GPU (for example `nvidia.com/gpu.product=NVIDIA-H100-80GB-HBM3` from GPU Feature Discovery).
- The `ExtendedResourceToleration` admission plugin (when enabled) auto-adds tolerations for taints named after an extended resource the pod requests.
- `NoExecute` also **evicts** running pods that don't tolerate it. Use `tolerationSeconds` for graceful moves.

---

## 6. "Pending" triage: the full decision tree

```
Pod Pending
├─ kubectl get pod -o jsonpath='{.spec.schedulerName}'
│    └─ not default-scheduler and that scheduler isn't running?  → no events at all. Fix the scheduler.
├─ spec.schedulingGates present?                                 → an external controller (e.g. Kueue) hasn't released it
├─ status.nominatedNodeName set?                                 → preemption in progress, victims terminating
├─ Events: FailedScheduling "0/N nodes are available: …"
│    ├─ Insufficient <res>         → requests too big / capacity used / GPU stack not advertising
│    ├─ untolerated taint          → add a toleration (and affinity!)
│    ├─ node affinity/selector     → labels wrong or missing (check GFD labels for GPU)
│    ├─ volume node affinity / unbound PVC → storage topology, StorageClass binding mode
│    └─ topology spread / anti-affinity   → constraints too strict for the node count
├─ Gang scheduler: PodGroup not satisfied (KAI/Volcano events, PodGroup status) → waiting for whole group
└─ No Pending pod at all, but a Job/Deployment is short of replicas → admission (ResourceQuota/LimitRange): check FailedCreate on the owner
```

Useful commands:

```bash
kubectl get events -A --field-selector reason=FailedScheduling --sort-by=.lastTimestamp
kubectl get pods -A --field-selector=status.phase=Pending -o wide
kubectl describe node <n> | sed -n '/Allocatable/,/Events/p'      # allocatable + allocated requests
kubectl get pod <p> -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")]}'
```

**Observability (ties into Lab 01):**
- kube-state-metrics: `kube_pod_status_unschedulable`, `kube_pod_status_phase{phase="Pending"}`.
- kube-scheduler metrics: `scheduler_pending_pods{queue="active|backoff|unschedulable|gated"}`, `scheduler_schedule_attempts_total{result}`, `scheduler_scheduling_attempt_duration_seconds`.
- Alert idea: `sum by (namespace) (kube_pod_status_unschedulable) > 0` for 10m → page with the FailedScheduling reason attached.

---

## 7. Why the default scheduler struggles with AI workloads

| Problem | What happens with kube-scheduler | What an AI scheduler adds |
|---|---|---|
| **All-or-nothing** | A 16-worker training job gets 10 pods placed. They hold 10 GPUs and wait forever for the other 6 (NCCL all-reduce needs every rank). Two such jobs can **deadlock** the cluster. (Lab 03, Exercise 6.) | **Gang scheduling** through PodGroups (`minMember`) |
| **Multi-tenancy** | Only per-namespace ResourceQuota (hard caps, enforced at admission). No borrowing of idle GPUs. | **Queues** with quota (guaranteed), over-quota weight, limit, priority; hierarchical; **DRF fair-share**; **reclaim** |
| **Fragmentation** | Spreading leaves 1 free GPU on many nodes | **Bin-packing** plus **consolidation** (moving pods to free whole nodes) |
| **Topology** | No idea of NVLink domains, racks or InfiniBand rails | **Topology-aware** placement of a whole gang (same rack / NVLink clique) |
| **Sharing** | Integer GPUs only | **Fractional GPU** booking |
| **Throughput at scale** | One pod per cycle | Job-level batch decisions, sharding |

---

## 8. KAI Scheduler (NVIDIA, open-sourced from Run:ai)

KAI is the Run:ai scheduling engine that NVIDIA open-sourced (Apache-2.0). It now lives at `github.com/kai-scheduler/KAI-Scheduler`. It runs **alongside** kube-scheduler, and a workload opts in.

**Components:** operator, admission webhook, **pod-grouper** (creates PodGroups from Jobs, JobSets, PyTorchJobs, RayClusters…), **scheduler** (builds a cluster snapshot and runs actions: allocate, consolidate, reclaim, preempt), **binder** (does binding separately, including GPU-sharing reservation pods), queue and podgroup controllers.

**Core objects:**
- **Queue** (`scheduling.run.ai/v2`): `quota` (guaranteed), `overQuotaWeight` (share of the surplus), `limit` (hard cap), `priority`, `parentQueue`. A fresh install creates `default-parent-queue` → `default-queue`.
- **PodGroup**: the gang. Its `minMember` pods must all fit or none run.

**Opting a workload in:**

```yaml
metadata:
  labels:
    kai.scheduler/queue: default-queue      # required
spec:
  schedulerName: kai-scheduler              # required
```

**Gang on a plain Job:** the annotation `kai.scheduler/batch-min-member: "N"` on the Job. Framework jobs (PyTorchJob, RayCluster, JobSet) get gangs automatically through the pod-grouper.

**Queue math (from KAI's docs):**
1. Every queue first gets `min(quota, requested)`. Priority is irrelevant in this phase.
2. Surplus goes to higher-**priority** queues first. Within the same priority, it's split by `overQuotaWeight`.
3. Workloads with priority ≥ 100 are **non-preemptible** and can only use in-quota resources. Lower-priority ones are preemptible and can borrow surplus, which can later be **reclaimed**.

**Fractional GPU:** annotation `gpu-fraction: "0.5"` (no `nvidia.com/gpu` in limits). In the default `NonMemoryEnforced` mode, memory **isn't** isolated.

**Hard-won ops notes:**
- Pods assigned to `kai-scheduler` **don't fall back** to the default scheduler. If KAI is down, they stay Pending with no events (same pattern as a wrong `schedulerName`).
- Don't submit workloads into the `kai-scheduler` namespace.
- NVIDIA's NVCF docs on KAI note that a Deployment gets one PodGroup **per replica**. Use a StatefulSet or a JobSet when replicas must be a single gang.

### The wider ecosystem (know the names for interviews)

| Tool | Model |
|---|---|
| **Kueue** | Job **admission** and quota queueing in front of the *default* scheduler (suspends and un-suspends Jobs). Doesn't replace kube-scheduler. |
| **Volcano** | A full batch scheduler (gangs, queues, fair-share), common in HPC/AI. |
| **scheduler-plugins coscheduling** | Adds a PodGroup gang to kube-scheduler through the Permit stage. |
| **Upstream Workload API + gang scheduling** | Alpha in Kubernetes v1.35, behind feature gates. The API was reworked in v1.36 (`v1alpha2`, Workload as template, PodGroup as runtime). It's the direction of travel, but **not production-ready yet**. Check the docs for your version. |
| **KAI** | Queues + DRF + gangs + bin-pack/consolidation + GPU fractions + topology. Integrates with KubeRay, Kubeflow Trainer, Grove/Dynamo. |

---

## 9. OpenShift angle

- The cluster scheduler is configured through the `Scheduler` CR: `oc get scheduler cluster -o yaml`.
  `spec.profile` can be **`LowNodeUtilization`** (default, spreads), **`HighNodeUtilization`** (bin-packs, which is good for GPU and cost), or **`NoScoring`** (fastest, filtering only).
- Custom or secondary schedulers run through the **Secondary Scheduler Operator**. Pods opt in with `schedulerName`, exactly as above.
- The NVIDIA GPU Operator on OpenShift (with the Node Feature Discovery operator) gives the same `nvidia.com/gpu` and GFD labels.
- KAI's install notes include OpenShift-specific flags (older gpu-operator versions need `admission.gpuFractionRuntimeClassName=""`. With CDI, use `binder.cdiEnabled=true`).
- Triage is identical: `oc describe pod`, `oc get events --field-selector reason=FailedScheduling`.

---

## 10. Interview drill (answer in 30 seconds each)

1. **"Walk me through what happens after `kubectl apply` of a pod."** Admission → etcd → scheduler watch → filter/score → binding → kubelet → CRI/CNI → probes.
2. **"Pod is Pending. What do you check?"** `schedulerName`, gates, `nominatedNodeName`, the FailedScheduling reason counts, node allocatable, taints/labels, PVC binding, quota (FailedCreate on the owner).
3. **"Does a toleration make a pod go to the GPU node?"** No. It permits. Affinity or a GPU request attracts.
4. **"Why can't a pod request 0.5 GPU?"** Extended resources are integers with no overcommit. Sharing needs time-slicing, MPS, MIG, DRA, or a scheduler with fraction support.
5. **"Cluster has 8 free GPUs, but a 4-GPU pod is Pending. Why?"** Fragmentation (spread placement). Fix it with a bin-pack scoring profile, consolidation, or a dedicated node pool.
6. **"Why gang scheduling?"** Distributed training needs every rank. Partial placement wastes GPUs and can deadlock two jobs against each other.
7. **"Kueue vs KAI vs Volcano?"** Kueue does admission/quota on top of kube-scheduler. KAI and Volcano are replacement schedulers with gangs, queues and fair-share.
8. **"How do you bin-pack on OpenShift?"** Set the Scheduler CR profile to `HighNodeUtilization`, or use a secondary scheduler with `MostAllocated`.

---

## 11. Corrections and nuances to the original post

The post is a good mental model. Here's what I'd add when going deeper:

- "Pending = zero nodes survived filtering" is the **common** case. It's not the only one: a wrong or absent scheduler, scheduling gates, preemption in flight, a gang that isn't complete yet, unbound volumes. Separately, quota rejections never even create a Pending pod.
- "Then it writes one field: the node name" is true in effect. Before that, Reserve/Permit/PreBind can do real work: volume binding, DRA allocation, gang waits.
- "Least allocated or most" is right, but the default `NodeResourcesFit` scoring **only considers cpu and memory** unless configured. GPUs are not part of default scoring at all.
- "Spread across zones and nodes" happens even with **no** constraints, because of the default system topology-spread constraints.

---

## Sources

- [Kubernetes: Scheduling Framework](https://kubernetes.io/docs/concepts/scheduling-eviction/scheduling-framework/) · [Scheduler config & default plugins](https://kubernetes.io/docs/reference/scheduling/config/) · [Resource bin packing](https://kubernetes.io/docs/concepts/scheduling-eviction/resource-bin-packing/) · [Scheduler performance tuning](https://kubernetes.io/docs/concepts/scheduling-eviction/scheduler-perf-tuning/)
- [Kubernetes: Gang Scheduling (alpha)](https://kubernetes.io/docs/concepts/scheduling-eviction/gang-scheduling/) · [v1.35 Workload Aware Scheduling blog](https://kubernetes.io/blog/2025/12/29/kubernetes-v1-35-introducing-workload-aware-scheduling/) · [KEP-4671](https://github.com/kubernetes/enhancements/blob/master/keps/sig-scheduling/4671-gang-scheduling/README.md)
- [KAI Scheduler repo](https://github.com/kai-scheduler/KAI-Scheduler): `docs/quickstart`, `docs/batch`, `docs/gpu-sharing`, `docs/scheduling-deep-dive` (read at commit `60f5433`, Nov 2026; latest tag v0.20.1)
- [NVIDIA blog: KAI Scheduler open-sourced](https://developer.nvidia.com/blog/nvidia-open-sources-runai-scheduler-to-foster-community-collaboration/)
- [Ray docs: KAI with KubeRay](https://docs.ray.io/en/latest/cluster/kubernetes/k8s-ecosystem/kai-scheduler.html)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/index.html) (time-slicing, MIG)
- [OpenShift: Scheduler profiles](https://docs.openshift.com/container-platform/latest/nodes/scheduling/nodes-scheduler-profiles.html)
