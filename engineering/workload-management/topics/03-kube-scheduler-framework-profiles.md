# 03 — kube-scheduler framework: filter, score, bind, scheduling profiles

**Layer:** 5 Scheduling
**Date:** 2026-11-26 · **Exercise:** ⚪ not run

## 1. What it is

kube-scheduler is a control loop with one job: for every pod with an empty `spec.nodeName`, pick a node and write that choice back to the API server. Since v1.19 all of its logic lives in plugins that hook into fixed **extension points** of the **scheduling framework**. A **scheduling profile** is a named set of enabled plugins, their weights and their arguments. One scheduler binary can serve several profiles, and a pod chooses one with `spec.schedulerName`.

The plugin tables (which filter gives which event text, default score weights, bin-packing) are already in the [Kubernetes scheduling deep dive](../../gpu-scheduling/KUBERNETES_SCHEDULING_DEEP_DIVE.md), sections 2.1 to 2.5. This note does not repeat them. It covers what the deep dive does not: the two cycles and the scheduler cache, how a config file becomes profiles, what must be equal across profiles, and how to run and observe a second profile on kind.

## 2. How it works at the infra layer

### Two cycles and an assumed cache

1. **Scheduling cycle (serial).** The scheduler pops one pod from activeQ and runs PreFilter, Filter, (PostFilter if no node fits), PreScore, Score, NormalizeScore, then Reserve and Permit. Filter and Score run in parallel across nodes (KubeSchedulerConfiguration `parallelism`, default 16 goroutines), but only one pod is in the scheduling cycle at a time.
2. **Assume.** After Reserve, the scheduler writes "pod X is on node Y" into its **in-memory cache** before the API server knows. The next pod is scheduled against this cache, so two pods do not both take the last free CPU.
3. **Binding cycle (asynchronous).** PreBind (for example volume binding or DRA allocation), Bind, PostBind run in a separate goroutine. The default `DefaultBinder` creates a `pods/binding` subresource. The API server then sets `spec.nodeName`, and the kubelet on that node starts the pod.
4. **Failure path.** If Permit denies, PreBind fails or Bind fails, the framework calls **Unreserve** on all Reserve plugins, removes the pod from the cache ("forget") and puts it back into the queue with backoff.

Permit can also return **wait**. The pod stays reserved but not bound until another plugin allows it or a timeout expires (the framework caps it at 15 minutes). Gang schedulers use this; see backlog topic 11.

What this means for an infra engineer: the scheduler's view of the cluster is **requests in its cache**, not real usage. It never reads `kubectl top`. A node at 10% real CPU can be "full" if requests add up to allocatable (topic [01](01-cgroups-v2-pod-qos.md)).

### From config file to profiles

The scheduler reads one file given with `--config`. The current API is `kubescheduler.config.k8s.io/v1` (`v1beta3` was removed in v1.29).

```yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
parallelism: 16
leaderElection:
  leaderElect: true
clientConnection:
  kubeconfig: /etc/kubernetes/scheduler.conf
profiles:
- schedulerName: default-scheduler        # default plugins, nothing changed
- schedulerName: no-scoring               # filter only: first feasible node wins
  plugins:
    preScore:
      disabled:
      - name: '*'
    score:
      disabled:
      - name: '*'
```

Rules worth remembering:

- **Every profile starts from the default plugin set.** You only write the changes (`enabled`, `disabled`, `pluginConfig`). `'*'` disables every default plugin at that extension point.
- **`multiPoint`** enables or disables a plugin at all extension points it implements, in one line. A setting at a specific extension point wins over `multiPoint`.
- **All profiles must use the same `queueSort` plugin and arguments.** There is only one pending-pods queue, so it can have only one sort order. This is the most common reason a multi-profile config fails to start.
- **`schedulerName` must be unique** per profile. A pod with no `schedulerName` gets `default-scheduler` from the API server.
- **`percentageOfNodesToScore`** can be set globally or per profile. It limits how many feasible nodes are searched before scoring (adaptive default). Low values trade placement quality for speed.
- `pluginConfig` holds plugin arguments, for example the `NodeResourcesFit` `scoringStrategy` (LeastAllocated, MostAllocated, RequestedToCapacityRatio).

### Profiles vs a second scheduler

| Option | One queue and cache | Can conflict on the same node | Use when |
|---|---|---|---|
| Extra **profile** in kube-scheduler | Yes | No, the cache is shared | Different scoring or plugin set, same binary |
| Separate **scheduler process** (Deployment) | No, each has its own | Yes, two schedulers can place pods on the same node at the same time; the kubelet then rejects one with `OutOfcpu` or similar | Out-of-tree plugins, or a different scheduler (Volcano, KAI) |

### Where to look on a node

On kubeadm and kind clusters, kube-scheduler is a static pod:

```bash
# Static pod manifest and its config
cat /etc/kubernetes/manifests/kube-scheduler.yaml
# Effective config is logged at startup with -v=1 or higher
kubectl -n kube-system logs kube-scheduler-<node> | head -50
# Who is the leader (HA control planes)
kubectl -n kube-system get lease kube-scheduler -o jsonpath='{.spec.holderIdentity}{"\n"}'
```

Useful metrics on port 10259 (`/metrics`, needs auth): `scheduler_schedule_attempts_total{result,profile}`, `scheduler_scheduling_attempt_duration_seconds`, `scheduler_pending_pods{queue}` and `scheduler_plugin_execution_duration_seconds`. These are covered in backlog topic 17.

### What is changing (v1.35 to v1.37)

- **Opportunistic batching** (KEP-5598, beta in v1.35, gate `OpportunisticBatching`): pods with the same "scheduling signature" can reuse the sorted node list of the previous pod instead of running the full Filter/Score pipeline. Pods with pod (anti-)affinity, topology spread or DRA claims are excluded.
- **Workload-aware scheduling** (alpha, `scheduling.k8s.io` Workload and PodGroup APIs, gates `GenericWorkload` and `GangScheduling`): a **PodGroup scheduling cycle** places a whole group at once, and new extension points (PlacementGenerate, PlacementScore, PodGroupPostFilter) appear in the config reference. These are alpha and off by default; backlog topic 11 covers them.

Check the docs for your exact version before you rely on any alpha or beta name.

## 3. Across platforms

| Kubernetes | OpenShift | HPC (Slurm) | AI training / inference |
|---|---|---|---|
| Edit `--config` of the kube-scheduler static pod; add profiles; pods choose with `schedulerName` | No direct edit of the default scheduler config. The `Scheduler` CR (`config.openshift.io/v1`, name `cluster`) offers `spec.profile`: `LowNodeUtilization` (default, spread), `HighNodeUtilization` (pack), `NoScoring`. Custom schedulers through the Secondary Scheduler Operator | `slurmctld` with `SchedulerType` (`sched/backfill`) and `SelectType` (`select/cons_tres`); no plugin framework, but partitions act like profiles | Default scheduler places pods one by one; gang, queueing and topology come from Kueue (admission, then normal scheduler) or a replacement scheduler (Volcano, KAI) chosen with `schedulerName`. GPU details: [AI-infra notes](../../notes/CURRICULUM.md) |

## 4. Failure modes and diagnosis

| Symptom | Cause | How to confirm | Fix |
|---|---|---|---|
| Pod Pending, **no events at all** | `schedulerName` points to a profile or scheduler that does not exist or is not running | `kubectl get pod P -o jsonpath='{.spec.schedulerName}'`; no `FailedScheduling` event | Fix the name, or start the scheduler |
| kube-scheduler crash-loops after config change | Profiles use different `queueSort`, duplicate `schedulerName`, wrong apiVersion or unknown plugin name | Static pod logs show the validation error | Fix the file; keep one `queueSort` for all profiles |
| `FailedScheduling: 0/N nodes are available ...` | No node passes Filter | Read the per-node reason counts (deep dive 2.3) | Fix requests, taints, affinity or capacity |
| Pod bound, then `OutOfcpu` / `OutOfmemory` on the node | Two independent schedulers placed pods on the same node in parallel | Events on the failed pod; two schedulers in use | Use profiles in one scheduler, or split nodes between schedulers with taints |
| Scheduling slow in a big cluster, `scheduler_pending_pods{queue="active"}` growing | Expensive plugins (pod affinity, topology spread) or a slow webhook / extender | `scheduler_plugin_execution_duration_seconds` by plugin | Remove required pod affinity where not needed; use profiles with fewer score plugins |
| Pod stays reserved but not bound for minutes | A Permit plugin returned wait (gang plugin), or PreBind waits for volume or DRA | Scheduler logs at `-v=4`; PVC or ResourceClaim status | Fix the group size or the storage/claim problem |

## 5. Exercise

**Goal:** run a second scheduler with two profiles on kind and prove which profile placed each pod. Runs on CPU-only kind. Status: ⚪ not run.

1. Create a cluster with two workers and read its version:

```bash
cat > kind-sched.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
EOF
kind create cluster --name sched --config kind-sched.yaml
VER=$(kubectl version -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)["serverVersion"]["gitVersion"])')
echo "$VER"
```

2. Create the scheduler config with two profiles. `lab-spread` keeps the defaults (LeastAllocated). `lab-pack` switches to MostAllocated and turns off the spreading score plugins. Leader election is off because only one replica runs.

```bash
cat > lab-scheduler-config.yaml <<'EOF'
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
leaderElection:
  leaderElect: false
profiles:
- schedulerName: lab-spread
- schedulerName: lab-pack
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
EOF
kubectl -n kube-system create configmap lab-scheduler-config \
  --from-file=lab-scheduler-config.yaml
```

3. Give it the same RBAC the upstream "Configure Multiple Schedulers" task uses, and run it as a Deployment with the image that matches the cluster version:

```bash
kubectl -n kube-system create serviceaccount lab-scheduler
kubectl create clusterrolebinding lab-scheduler-kube \
  --clusterrole=system:kube-scheduler --serviceaccount=kube-system:lab-scheduler
kubectl create clusterrolebinding lab-scheduler-volume \
  --clusterrole=system:volume-scheduler --serviceaccount=kube-system:lab-scheduler
kubectl -n kube-system create rolebinding lab-scheduler-auth \
  --role=extension-apiserver-authentication-reader --serviceaccount=kube-system:lab-scheduler

cat > lab-scheduler.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lab-scheduler
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels: {app: lab-scheduler}
  template:
    metadata:
      labels: {app: lab-scheduler}
    spec:
      serviceAccountName: lab-scheduler
      containers:
      - name: kube-scheduler
        image: registry.k8s.io/kube-scheduler:${VER}
        command:
        - /usr/local/bin/kube-scheduler
        - --config=/etc/lab/lab-scheduler-config.yaml
        - --v=2
        volumeMounts:
        - {name: config, mountPath: /etc/lab}
      volumes:
      - name: config
        configMap: {name: lab-scheduler-config}
EOF
kubectl apply -f lab-scheduler.yaml
kubectl -n kube-system rollout status deploy/lab-scheduler
```

4. Create four small pods for each profile (100m CPU each), plus one pod with a wrong scheduler name:

```bash
for prof in lab-spread lab-pack; do
  for i in 1 2 3 4; do
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${prof}-$i
spec:
  schedulerName: ${prof}
  containers:
  - name: pause
    image: registry.k8s.io/pause:3.10
    resources:
      requests: {cpu: 100m}
EOF
  done
done
kubectl run orphan --image=registry.k8s.io/pause:3.10 \
  --overrides='{"spec":{"schedulerName":"does-not-exist"}}'
```

5. Check placement and which profile reported each event:

```bash
kubectl get pods -o custom-columns=NAME:.metadata.name,SCHED:.spec.schedulerName,NODE:.spec.nodeName
kubectl get events --field-selector reason=Scheduled \
  -o custom-columns=POD:.involvedObject.name,BY:.reportingComponent
kubectl describe pod orphan | tail -3
```

Expected output (illustrative, node names differ):

```text
NAME           SCHED            NODE
lab-pack-1     lab-pack         sched-worker2
lab-pack-2     lab-pack         sched-worker2
lab-pack-3     lab-pack         sched-worker2
lab-pack-4     lab-pack         sched-worker2
lab-spread-1   lab-spread       sched-worker
lab-spread-2   lab-spread       sched-worker2
lab-spread-3   lab-spread       sched-worker
lab-spread-4   lab-spread       sched-worker2
orphan         does-not-exist   <none>

POD            BY
lab-spread-1   lab-spread
lab-pack-1     lab-pack
...
Events:          <none>
```

What to read from it: `lab-pack` puts all pods on one worker (the order in which pods are created can change which one), `lab-spread` alternates. The event's reporting component is the **profile name**, which is how you prove which profile made a decision. The orphan pod has no events at all, because no scheduler owns that name.

**Evidence to capture:** outputs of step 5, `kubectl version`, and the first 30 lines of `kubectl -n kube-system logs deploy/lab-scheduler`. Clean up with `kind delete cluster --name sched`.

## 6. Interview angle

- **"What is the difference between a scheduling profile and a second scheduler?"** A profile is a plugin set inside one scheduler process: one queue, one cache, no placement races. A second scheduler has its own cache, so two schedulers can overbook a node; use taints or node pools to separate them.
- **"A pod is Pending and `kubectl describe` shows no events. Where do you look?"** At `spec.schedulerName`. No `FailedScheduling` event means no scheduler tried. Then check that the scheduler pod is running and, in HA, holds the lease.
- **"Why does the scheduler not see real CPU usage?"** It schedules against requests in its own cache, updated at Reserve ("assume") before binding. Real usage only matters later, at the kubelet (eviction, throttling).

## Sources

- Kubernetes docs, [Scheduling framework](https://kubernetes.io/docs/concepts/scheduling-eviction/scheduling-framework/) (extension points, Permit, Unreserve)
- Kubernetes docs, [Scheduler configuration](https://kubernetes.io/docs/reference/scheduling/config/) (profiles, `multiPoint`, `queueSort` rule, default plugins)
- Kubernetes docs, [kube-scheduler configuration (v1) API](https://kubernetes.io/docs/reference/config-api/kube-scheduler-config.v1/) (`parallelism`, `percentageOfNodesToScore`)
- Kubernetes docs, [Configure multiple schedulers](https://kubernetes.io/docs/tasks/extend-kubernetes/configure-multiple-schedulers/) (RBAC and Deployment pattern used in the exercise)
- Kubernetes docs, [Running multiple schedulers](https://kubernetes.io/docs/concepts/scheduling-eviction/running-multiple-schedulers/)
- KEP-5598, [Opportunistic batching](https://www.kubernetes.dev/resources/keps/5598/)
- Kubernetes blog, [v1.36: Advancing workload-aware scheduling](https://kubernetes.io/blog/2026/05/13/kubernetes-v1-36-advancing-workload-aware-scheduling/)
- Red Hat, [Scheduler config API (OpenShift 4.20)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/config_apis/scheduler-config-openshift-io-v1) and [OKD scheduler profiles](https://docs.okd.io/4.20/nodes/scheduling/nodes-scheduler-profiles.html)
- Slurm, [slurm.conf](https://slurm.schedmd.com/slurm.conf.html) (`SchedulerType`, `SelectType`)
