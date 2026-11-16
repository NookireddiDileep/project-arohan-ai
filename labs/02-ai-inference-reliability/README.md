# AROHAN Lab 02: AI Inference Reliability. Run an LLM on Kubernetes, govern it, break it, fix it

## Status

**LAB 02: PLANNED 🟡** (builds on [Lab 01: Workload Reliability Foundation](../01-gpu-workload-reliability/README.md))

**Project:** AROHAN AI · AI Workload Reliability track (Kubernetes → GPU → AI inference)
**Cluster:** existing GCP K3s cluster `platform-engineer-lab` (CPU only, no GPU cost)
**Time:** about 6–8 hours, split across 3–4 sessions
**Covers guide labs:** 01 (deploy) · 02 (serve a model) · 03 (Service) · 09 (benchmark) · 10 (failures and RCAs), plus a **workload management** layer of quotas, limits and scheduling

> Goal: show that you can operate an AI workload like a production platform engineer, not just run a model.
> Every break in Part 5 ends with an RCA in `incidents/`.

---

## Part 0: Pre-checks (15 min)

```bash
kubectl version
kubectl get nodes -o wide
kubectl top nodes                 # K3s ships metrics-server
kubectl get storageclass          # K3s default: local-path
kubectl describe node <node> | grep -A6 "Allocatable"
```

Record the free CPU and memory per node. Use **qwen2.5:0.5b** (~0.4 GB) to start, and move to **qwen2.5:1.5b** (~1 GB) only if a node has ≥4 GB free. If your storage class isn't `local-path`, change it in `02-pvc.yaml`.

---

## Part 1: Create a governed namespace (workload management)

`manifests/01-namespace-quota.yaml`
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ai-lab
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ai-lab-quota
  namespace: ai-lab
spec:
  hard:
    requests.cpu: "3"
    requests.memory: 6Gi
    limits.cpu: "4"
    limits.memory: 8Gi
    persistentvolumeclaims: "3"
    pods: "6"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: ai-lab-defaults
  namespace: ai-lab
spec:
  limits:
  - type: Container
    default:        { cpu: "500m", memory: 512Mi }   # applied if a pod sets no limits
    defaultRequest: { cpu: "100m", memory: 128Mi }
    max:            { cpu: "2",    memory: 6Gi }
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: inference-critical
value: 100000
globalDefault: false
description: "Model-serving pods: preempt batch/test pods under pressure"
```

```bash
kubectl apply -f manifests/01-namespace-quota.yaml
kubectl describe quota -n ai-lab
```

---

## Part 2: Deploy Ollama with storage, probes and resource limits

`manifests/02-pvc.yaml`
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ollama-models
  namespace: ai-lab
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-path
  resources:
    requests:
      storage: 10Gi
```

`manifests/03-ollama.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ollama
  namespace: ai-lab
  labels: { app: ollama }
spec:
  replicas: 1
  strategy: { type: Recreate }        # RWO volume: avoid two pods fighting over it
  selector:
    matchLabels: { app: ollama }
  template:
    metadata:
      labels: { app: ollama }
    spec:
      priorityClassName: inference-critical
      containers:
      - name: ollama
        image: ollama/ollama:latest   # TODO: pin a specific tag from Docker Hub before committing
        ports:
        - containerPort: 11434
          name: http
        env:
        - name: OLLAMA_HOST
          value: "0.0.0.0:11434"
        - name: OLLAMA_MODELS
          value: /models               # explicit path; also matters on OpenShift (Part 6)
        - name: OLLAMA_KEEP_ALIVE
          value: "30m"                 # keep model in memory between requests
        volumeMounts:
        - name: models
          mountPath: /models
        resources:
          requests: { cpu: "1",  memory: 2Gi }
          limits:   { cpu: "2",  memory: 4Gi }
        startupProbe:
          httpGet: { path: /, port: http }
          periodSeconds: 5
          failureThreshold: 24          # up to 2 min to start
        readinessProbe:
          httpGet: { path: /, port: http }
          periodSeconds: 10
        livenessProbe:
          httpGet: { path: /, port: http }
          periodSeconds: 20
          failureThreshold: 3
      volumes:
      - name: models
        persistentVolumeClaim:
          claimName: ollama-models
---
apiVersion: v1
kind: Service
metadata:
  name: ollama
  namespace: ai-lab
spec:
  type: ClusterIP                       # internal only: never expose an unauthenticated model API publicly
  selector: { app: ollama }
  ports:
  - name: http
    port: 11434
    targetPort: http
```

```bash
kubectl apply -f manifests/02-pvc.yaml -f manifests/03-ollama.yaml
kubectl -n ai-lab rollout status deploy/ollama
kubectl -n ai-lab get pods,pvc,svc,endpointslices
kubectl -n ai-lab logs deploy/ollama
```

**Checkpoint:** the pod is `Running 1/1`, the PVC is `Bound`, and the EndpointSlice lists the pod IP.

---

## Part 3: Pull a model and run inference

```bash
kubectl -n ai-lab exec deploy/ollama -- ollama pull qwen2.5:0.5b
kubectl -n ai-lab exec deploy/ollama -- ollama list

# Call the API through the Service from a throwaway client pod (tests DNS + Service + endpoints)
kubectl -n ai-lab run client --rm -it --restart=Never --image=curlimages/curl -- \
  curl -s http://ollama.ai-lab.svc.cluster.local:11434/api/generate \
  -d '{"model":"qwen2.5:0.5b","prompt":"Explain a Kubernetes readiness probe in 2 lines.","stream":false}'
```

The JSON response includes the timings you'll need in Part 4: `load_duration`, `prompt_eval_duration`, `eval_count` and `eval_duration` (all durations in nanoseconds).

---

## Part 4: Benchmark baseline (always measure, never guess)

Run this from a long-lived client pod so the network path stays the same between runs:

```bash
kubectl -n ai-lab run bench --image=alpine:3 --restart=Never -- sleep 3600
kubectl -n ai-lab exec -it bench -- sh -c "apk add -q curl jq"
```

`load-testing/bench.sh` (copy into the pod with `kubectl cp`, or paste it in):
```sh
#!/bin/sh
# usage: bench.sh <model> <requests>
M=${1:-qwen2.5:0.5b}; N=${2:-10}
URL=http://ollama.ai-lab.svc.cluster.local:11434/api/generate
P='Write 3 bullet points on Linux cgroups.'
echo "run,total_s,first_token_s,tokens,tok_per_s"
i=1
while [ $i -le $N ]; do
  curl -s $URL -d "{\"model\":\"$M\",\"prompt\":\"$P\",\"stream\":false,\"options\":{\"num_predict\":128}}" |
  jq -r --arg i $i '[$i,
    (.total_duration/1e9),
    ((.load_duration+.prompt_eval_duration)/1e9),
    .eval_count,
    (.eval_count/(.eval_duration/1e9))] | @csv'
  i=$((i+1))
done
```

Run it three ways and record every result in `load-testing/benchmark-results.md`:

| Test | Command | Record |
|---|---|---|
| Cold vs warm | first request vs requests 2–10 | first-token time (approx.), total time |
| Sequential | `bench.sh qwen2.5:0.5b 10` | p50 / p95 total time, tokens/s |
| Concurrency 4 | run 4 copies in parallel (`for i in 1 2 3 4; do sh bench.sh & done; wait`) | p95 latency, tokens/s, and `kubectl top pod -n ai-lab` |

Note the hardware, model, prompt, `num_predict` and concurrency next to each result. Without those, the numbers can't be compared.

---

## Part 5: Break it, fix it, write the RCA (the most valuable part)

For each incident: **break → observe symptoms → diagnose with commands → fix → verify → write `incidents/00X-*.md`.** Try to diagnose before reading the hint.

### Incident 001: Model pod OOMKilled
- **Break:** set `limits.memory: 512Mi` in `03-ollama.yaml`, apply, then pull and run `qwen2.5:1.5b`.
- **Observe:** the request fails or hangs; the pod restarts.
- **Diagnose:** `kubectl -n ai-lab get pod -w` · `kubectl describe pod` (Last State: OOMKilled, Exit 137) · `kubectl top pod` · `kubectl get events --sort-by=.lastTimestamp`
- **Fix:** size limits to model RAM plus overhead. Explain why the request and the limit differ.

### Incident 002: Service has no endpoints (the "API down" case)
- **Break:** change the Service selector to `app: ollama-v2`.
- **Observe:** the client curl fails while the pod looks perfectly healthy.
- **Diagnose:** `kubectl get endpointslices -n ai-lab` (empty) · `kubectl get pods --show-labels` · compare against `kubectl get svc ollama -o yaml`
- **Fix:** correct the selector. Interview point: "the pod is Running" does not mean the service is up.

### Incident 003: Models disappear after a restart
- **Break:** replace the PVC volume with `emptyDir: {}`, apply, pull a model, then `kubectl delete pod -l app=ollama`.
- **Observe:** `ollama list` is empty after the restart, and the first request is slow while it re-pulls.
- **Diagnose:** `kubectl get pod -o yaml | grep -A5 volumes` · `kubectl get pvc`
- **Fix:** restore the PVC. Also note: `Recreate` strategy plus RWO volume plus `local-path` ties the pod to one node. Write down what that means for node failure.

### Incident 004: Quota blocks a new model deployment (workload management)
- **Break:** copy the Deployment as `ollama-2` with `requests.memory: 5Gi`.
- **Observe:** no pod appears.
- **Diagnose:** `kubectl -n ai-lab get rs` · `kubectl describe rs <ollama-2-rs>` ("exceeded quota") · `kubectl describe quota -n ai-lab`
- **Fix / decide:** right-size the request, raise the quota with a justification, or schedule the second model elsewhere. Write it as a capacity decision, not just a fix.

### Incident 005: Pod stuck Pending (scheduler)
- **Break:** temporarily raise the quota, then set `requests.memory` above any node's allocatable memory.
- **Diagnose:** `kubectl describe pod` → `0/N nodes are available: Insufficient memory` · compare with `kubectl describe node`
- **Fix:** right-size it. Then explain how `inference-critical` priority would preempt lower-priority pods, and test it with a low-priority "batch" pod.

### RCA template (`incidents/TEMPLATE.md`)
```markdown
# INC-00X: <title>
- Date / environment:
- Impact: (who/what was affected, duration)
- Symptoms observed:
- Timeline: (detection → diagnosis → fix → verified)
- Diagnosis: (commands run + key output)
- Root cause:
- Fix applied:
- Verification:
- Prevention: (alert, policy, quota, probe, GitOps check…)
- Interview takeaway: (2 lines)
```

---

## Part 6: Bonus, repeat on OpenShift (shared training cluster, with permission)

Deploy the same manifests in a project on an OpenShift cluster, keeping the default `restricted-v2` SCC.
- **What usually happens:** the image expects to run as root and write under its home directory, but OpenShift runs pods as a random non-root UID. You'll likely see permission errors.
- **Your task:** diagnose it (`oc describe pod`, `oc logs`, `oc get pod -o yaml | grep -i scc`) and fix it the right way, using writable mounted paths (`OLLAMA_MODELS=/models`, `HOME` pointing to a writable volume). **Don't** grant `anyuid` unless you can justify it.
- Expose it with a Route secured by edge TLS, and keep it internal or behind auth.
- That's incident 006, and a strong OpenShift interview story.

---

## Exercises

| Exercise | Focus | Status |
|---|---|---|
| [02B: Inference latency breakdown and scale-out delay](exercises/02B-inference-latency-breakdown.md) | Time the deployment flow vs the request flow (queue, prefill, decode), readiness after model load, HPA scale-out delay, quota limits | PLANNED 🟡 |

Theory: [AI Inference on Kubernetes: Where the Time Goes](../../engineering/ai-inference/INFERENCE_ON_KUBERNETES.md)

---

## Deliverables

```
labs/02-ai-inference-reliability/
├── README.md                 # this guide + your notes and screenshots
├── manifests/                # 01-namespace-quota, 02-pvc, 03-ollama
├── load-testing/             # bench.sh + benchmark-results.md
├── incidents/                # TEMPLATE.md + 001–005 (+006 OpenShift) RCAs
└── evidence/                 # screenshots and command output
```

**Done when:** the model answers through the Service, the benchmark table is filled in, at least 3 RCAs are written, and you can explain each incident in about 2 minutes.

**Link to Lab 01:** Prometheus and kube-state-metrics are already running in `arohan-observability` (Lab 01). Point the Lab 01 memory-pressure rule at the `ai-lab` namespace and confirm it fires during Incident 001, then add Grafana panels for pod CPU and memory, restarts, OOM events and request latency.

**Next lab (03):** vLLM vs Ollama comparison, then GPU Operator on a spot GPU node.

> Keep the guide's 70/20/10 split: this lab is your 20% AI track and must not slow down EX280 prep.
