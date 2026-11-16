# AROHAN Lab 03: GPU Scheduling. Filter, score, fragment, deadlock, then fix it with gangs

## Status

**LAB 03: PLANNED 🟡** (theory: [Kubernetes Scheduling deep dive](../../engineering/gpu-scheduling/KUBERNETES_SCHEDULING_DEEP_DIVE.md))

**Project:** AROHAN AI · Architecture capability **6. GPU Scheduling**
**Cluster:** `kind` on a laptop or a GCP VM (Docker). **No real GPU needed.** Fake GPUs are used. Baseline cluster: about 2 vCPU / 4 GB free. KAI cluster (Ex. 7): about 4 vCPU / 8 GB free.
**Time:** about 5–6 hours across 3 sessions (Ex. 0–4 · Ex. 5–6 · Ex. 7)
**Tools:** `docker`, `kind` ≥ 0.27, `kubectl` ≥ 1.30, `helm` ≥ 3.14 (Ex. 7 only), `jq` (optional)

> Goal: prove, with evidence, every claim in the theory doc. That covers how the scheduler filters and scores, why defaults fragment GPUs, why pod-at-a-time scheduling deadlocks distributed jobs, and how an AI scheduler (KAI) fixes it.
> **Honesty note:** the manifests are YAML/bash syntax-checked but have **not yet been run end to end**. The first run is the validation. Record anything that differs in `evidence/`.

### How the fake GPUs work

- **Ex. 0–6:** we PATCH node **status** to advertise `nvidia.com/gpu: 4` on two workers. This is the documented "advertise an extended resource for a node" technique. The scheduler treats it exactly like a real device-plugin GPU (integer, no overcommit, `Insufficient nvidia.com/gpu`). Containers just `sleep`, because nothing can actually *use* a GPU.
- **Ex. 7:** run-ai's **fake-gpu-operator**, the same thing KAI's own CI uses on kind. It gives 8 fake GPUs per node plus the GPU metadata KAI needs.

### Engineering lifecycle (AROHAN model)

| Stage | Where |
|---|---|
| Problem | Ex. 5 (fragmentation), Ex. 6 (gang deadlock) |
| Architecture | theory doc §2, §7, §8 |
| Implementation | Ex. 5c bin-pack scheduler, Ex. 7 KAI |
| Failure injection | Ex. 1c, 2, 3a, 4, 5b, 6 |
| Diagnosis | FailedScheduling reason counts, `scripts/placement.sh` |
| Recovery / verification | Ex. 5e, 7b |
| Evidence | `evidence/` (checklist at the bottom) |

---

## Exercise 0: Build the lab (20 min)

```bash
cd labs/03-gpu-scheduling
kind create cluster --name sched-lab --image kindest/node:v1.35.0 --config manifests/00-kind-sched-lab.yaml
kubectl get nodes -L node-type,gpu-model
./scripts/fake-gpus.sh                     # 4 fake GPUs + NoSchedule taint on each node-type=gpu worker
kubectl apply -f manifests/00-namespace.yaml
```

**Expect:** `sched-lab-worker` = cpu, `sched-lab-worker2` and `sched-lab-worker3` = gpu, each with `GPU_ALLOCATABLE 4` and a `nvidia.com/gpu` taint.
**Check yourself:** `kubectl describe node sched-lab-worker2 | sed -n '/Capacity/,/System Info/p'`. Capacity vs Allocatable. Where did the GPU show up?

Reset between exercises with `./scripts/reset.sh`.

---

## Exercise 1: The pipeline. The scheduler only writes a node name (30 min)

**1a. Normal path**
```bash
kubectl -n sched-lab get events -w &          # leave running
kubectl apply -f manifests/01a-plain-pod.yaml
kubectl -n sched-lab get pod plain -o jsonpath='{.spec.nodeName}{"\n"}{.status.conditions[?(@.type=="PodScheduled")]}{"\n"}'
kill %1
```
Expect the `Scheduled` event (source: default-scheduler), then `Pulling` / `Created` / `Started` (source: kubelet). **Two different actors.**

**1b. Skip the scheduler**
```bash
kubectl apply -f manifests/01b-nodename-bypass.yaml
kubectl -n sched-lab get pod bypass -o wide
kubectl -n sched-lab get events --field-selector involvedObject.name=bypass
```
Expect: Running **on a tainted GPU node with no toleration**, and **no `Scheduled` event**. `NoSchedule` is a scheduler rule, and the scheduler never saw this pod.
**Ops lesson:** `nodeName` in a manifest is a footgun. Use `nodeSelector` or affinity.

**1c. Orphaned pod**
```bash
kubectl apply -f manifests/01c-wrong-scheduler.yaml
sleep 30; kubectl -n sched-lab describe pod orphan | tail -5
```
Expect: Pending, `Events: <none>`. **No events at all means no scheduler owns this pod.** Same symptom as "KAI is down".

---

## Exercise 2: Filtering. Read the reason counts (30 min)

```bash
./scripts/reset.sh
for f in 02a 02b 02c; do kubectl apply -f manifests/${f}-*.yaml; done
sleep 10
kubectl -n sched-lab get events --field-selector reason=FailedScheduling -o custom-columns='POD:.involvedObject.name,MSG:.message'
```

For each pod, write the message down and **explain every number** (they must add up to 4 nodes):

| Pod | Expected reasons (roughly) |
|---|---|
| `greedy` (8 GPUs) | control-plane: untolerated taint · cpu worker + 2 gpu workers: `Insufficient nvidia.com/gpu` |
| `no-toleration` | control-plane: taint · 2 gpu workers: untolerated taint `nvidia.com/gpu` · cpu worker: `Insufficient nvidia.com/gpu` |
| `wants-h100` | control-plane: taint · 3 workers: `didn't match Pod's node affinity/selector` |

Note the "preemption: 0/4 nodes are available: … No preemption victims found" tail. That's PostFilter running and also failing.

**Fix each one** (edit and re-apply) and record the fix: lower the GPU count, add the toleration, use `gpu-model: fake-a100`.

---

## Exercise 3: Taints repel, tolerations permit, affinity attracts (20 min)

```bash
./scripts/reset.sh
kubectl apply -f manifests/03a-toleration-only.yaml
kubectl -n sched-lab get pods -l app=tolerate-only -o wide
kubectl apply -f manifests/03b-toleration-plus-affinity.yaml
kubectl -n sched-lab get pods -l app=tolerate-and-attract -o wide
```
Expect: `tolerate-only` replicas on **all three workers, the CPU one included**. `tolerate-and-attract` only on worker2 and worker3.
**Interview line:** "A toleration is a permission slip, not a magnet."

---

## Exercise 4: Requests decide placement. Limits decide runtime (30 min)

```bash
./scripts/reset.sh
kubectl apply -f manifests/04a-huge-request.yaml      # Pending: Insufficient memory, on idle nodes
kubectl apply -f manifests/04b-half-gpu.yaml          # REJECTED by the API server (integer resource)
kubectl apply -f manifests/04c-gpu-overcommit.yaml    # REJECTED: request must equal limit for nvidia.com/gpu
kubectl apply -f manifests/04d-oom.yaml
kubectl -n sched-lab get pod oom-demo -w              # Running → OOMKilled → CrashLoopBackOff
kubectl -n sched-lab get pod oom-demo -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}'
kubectl -n sched-lab get pod oom-demo -o jsonpath='{.status.qosClass}{"\n"}'
```
Record the **exact** API error text for 4b and 4c. They prove the rejection happens at validation, before the scheduler. 4d proves the scheduler placed a pod that the kernel then killed. Placement looked only at the 50Mi request.

---

## Exercise 5: Fragmentation, then fix it with a bin-packing scheduler (60 min)

**5a/5b. Default scheduler (spread)**
```bash
./scripts/reset.sh
kubectl apply -f manifests/05a-small-gpu-default.yaml
kubectl -n sched-lab rollout status deploy/small-infer
./scripts/placement.sh
kubectl apply -f manifests/05b-big-gpu-default.yaml
sleep 10; ./scripts/placement.sh
```
Expect: `small-infer` spread **2 + 2** across worker2 and worker3, and `big-train` (4 GPUs) **Pending** with `Insufficient nvidia.com/gpu`, **while 4 GPUs sit free in the cluster**.
If you got 3 + 1 or 4 + 0, record it. Placement is scoring-driven, not guaranteed. Then explain which score plugins pushed it there (LeastAllocated on cpu/memory, default topology spread).

**5c. Deploy a second scheduler with a bin-pack profile**
```bash
kubectl apply -f manifests/05c-binpack-scheduler.yaml
kubectl -n kube-system rollout status deploy/binpack-scheduler
kubectl -n kube-system logs deploy/binpack-scheduler | head -30
```
Read the ConfigMap in `05c`. `MostAllocated`, `nvidia.com/gpu` weight 5, BalancedAllocation and PodTopologySpread scoring disabled. Why disable those two?

**5d/5e. Same workload, packed**
```bash
./scripts/reset.sh
kubectl apply -f manifests/05d-small-gpu-binpack.yaml
kubectl -n sched-lab rollout status deploy/small-infer-packed
./scripts/placement.sh                                   # expect 4 + 0
kubectl apply -f manifests/05e-big-gpu-binpack.yaml
sleep 10; ./scripts/placement.sh                         # expect big-train-packed Running on the empty node
```
**Deliverable:** a before/after table (default vs binpack: per-node GPU allocation, big-train status) in `evidence/EX05-fragmentation.md`.
**OpenShift equivalent:** `oc patch scheduler cluster --type=merge -p '{"spec":{"profile":"HighNodeUtilization"}}'` (cluster-wide, so do it on a lab cluster only).

> Stretch: run the bin-pack scheduler with `--v=10` and grep the logs for per-plugin scores. Log keys vary by version, so note what you find.

---

## Exercise 6: The gang deadlock (30 min)

```bash
./scripts/reset.sh
kubectl -n kube-system scale deploy/binpack-scheduler --replicas=0   # use the default scheduler only
kubectl apply -f manifests/06-gang-deadlock.yaml
sleep 20; ./scripts/placement.sh
kubectl -n sched-lab get jobs
```
Expect: 8 Running and 2 Pending, **split across both jobs** (e.g. 4 + 4, or 5 + 3).
- If the split is 4 + 4: **neither** job can ever start real training. 8 GPUs are burning and nobody is making progress. That's a deadlock.
- If one job got 5: run it again (`reset.sh`). Getting a working job is **luck, not policy**. That's the point.

**Write in `evidence/EX06-gang-deadlock.md`:** how many GPUs are held by jobs that can't make progress? What would the cost be on 8× H100 for one hour?

---

## Exercise 7: KAI Scheduler, the same problems solved (90 min)

New cluster, so keep `sched-lab` or delete it (`kind delete cluster --name sched-lab`).

```bash
kind create cluster --name kai-lab --image kindest/node:v1.35.0 --config manifests/07a-kind-kai-lab.yaml
./scripts/install-kai.sh            # fake-gpu-operator 0.2.0 + KAI v0.19.0 (pinned)
kubectl -n kai-scheduler get pods   # operator, admission, binder, podgrouper, scheduler, queue/podgroup controllers
kubectl get queues                  # default-parent-queue → default-queue
```
Expect 2 nodes with `nvidia.com/gpu: 8`.
> If the fake operator or KAI chart doesn't come up, compare with KAI's own `hack/setup-e2e-cluster.sh` at the same tag. It's the reference this script was derived from.

**7b. Gang scheduling vs Exercise 6**
```bash
kubectl apply -f manifests/07b-gang-jobs-kai.yaml
sleep 30
./scripts/placement.sh kai-lab
kubectl -n kai-lab get podgroups.scheduling.run.ai
kubectl -n kai-lab describe podgroups.scheduling.run.ai | grep -A5 -i -E 'condition|event'
```
Expect: **one job 10/10 Running, the other 0/10 Pending** with a PodGroup reason explaining the gang can't fit. Then:
```bash
kubectl -n kai-lab delete job gang-a     # or whichever is running
sleep 20; ./scripts/placement.sh kai-lab # the other gang starts as a whole
```

**7c. Fractional GPUs**
```bash
kubectl apply -f manifests/07c-fractional-gpu-kai.yaml
./scripts/placement.sh kai-lab
kubectl -n kai-resource-reservation get pods -o wide   # KAI's reservation pods: one per shared physical GPU
```
Expect 4 pods on about 2 shared GPUs. **Write down:** what stops pod A from using all of the GPU memory? (Answer: nothing, in `NonMemoryEnforced` mode.)

**7d. Stretch: queues and fair-share**
```bash
kubectl apply -f manifests/07d-queues-kai.yaml && kubectl get queues
```
Copy `07b`, put one job in `team-a` asking for 16 GPUs, then submit 8 GPUs to `team-b`. Observe borrowing (over-quota) and whether KAI **reclaims** from team-a. Read `docs/scheduling-deep-dive` in the KAI repo first. Preemptibility depends on `priorityClassName` (priority < 100 is preemptible).

---

## Evidence checklist (Definition of Done)

| File in `evidence/` | Contents |
|---|---|
| `EX00-cluster.md` | node list, allocatable with fake GPUs, taints |
| `EX01-pipeline.md` | events of 1a (scheduler vs kubelet), 1b no-Scheduled-event proof, 1c `Events: <none>` |
| `EX02-filter-reasons.md` | 3 FailedScheduling messages, each number explained, and the fix |
| `EX03-taints-affinity.md` | placement tables for 3a vs 3b |
| `EX04-requests-limits.md` | API rejection texts, OOMKilled proof, QoS class |
| `EX05-fragmentation.md` | before/after placement + Pending→Running proof |
| `EX06-gang-deadlock.md` | split placement, GPUs wasted, cost reasoning |
| `EX07-kai.md` | gang all-or-nothing proof, fractional placement, queue observations |
| `LAB03-VALIDATION.md` | what matched the expected results, what didn't, and why |

Screenshots go next to them (`NN AROHAN LAB 03 — <title>.png`), following Lab 01's naming.

## Cleanup

```bash
kind delete cluster --name sched-lab
kind delete cluster --name kai-lab
```
