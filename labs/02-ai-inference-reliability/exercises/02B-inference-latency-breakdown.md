# Lab 02 · Exercise 02B: Inference latency breakdown and scale-out delay

**Status:** PLANNED 🟡 · **Prerequisite:** Lab 02 Parts 0–3 done (Ollama running in `ai-lab`)
**Theory:** [engineering/ai-inference/INFERENCE_ON_KUBERNETES.md](../../../engineering/ai-inference/INFERENCE_ON_KUBERNETES.md)
**Time:** about 3–4 hours · CPU only on K3s

> Goal: stop saying "inference is slow". Measure **where** the time goes, in both the deployment flow and the request flow, and prove why scaling out an AI workload is slower than scaling a web app.

---

## Part 1: Time the deployment flow (Flow A)

Restart the pod and capture each stage's timestamp from Kubernetes itself:

```bash
kubectl -n ai-lab rollout restart deploy/ollama
kubectl -n ai-lab rollout status deploy/ollama
POD=$(kubectl -n ai-lab get pod -l app=ollama -o jsonpath='{.items[0].metadata.name}')

# Creation and condition transition times
kubectl -n ai-lab get pod $POD -o json | jq -r '
  "created:          \(.metadata.creationTimestamp)",
  (.status.conditions[] | "\(.type): \(.lastTransitionTime)")'

# Image pull duration (shows "Successfully pulled image ... in Xs" unless cached)
kubectl -n ai-lab get events --field-selector involvedObject.name=$POD \
  --sort-by=.lastTimestamp -o custom-columns=TIME:.lastTimestamp,REASON:.reason,MSG:.message
```

Now time the **model** part, which Kubernetes can't see:

```bash
# Model download (weights → PVC): delete and re-pull to time it
kubectl -n ai-lab exec deploy/ollama -- ollama rm qwen2.5:0.5b
time kubectl -n ai-lab exec deploy/ollama -- ollama pull qwen2.5:0.5b

# Model load into memory: first request after a restart. Read load_duration (ns)
kubectl -n ai-lab exec bench -- sh -c \
 'curl -s http://ollama:11434/api/generate -d "{\"model\":\"qwen2.5:0.5b\",\"prompt\":\"hi\",\"stream\":false}" | jq "{load_s: (.load_duration/1e9)}"'
```

Fill this table in `../load-testing/benchmark-results.md`:

| Stage | Source | Seconds |
|---|---|---|
| Created → PodScheduled | conditions | |
| Image pull | events | |
| Container start → Ready | conditions | |
| Model download | `time ollama pull` | |
| Model load to memory | `load_duration` | |
| **Total "new replica useful"** | sum | |

**Question to answer in your notes:** the pod showed `Ready` before the model was loaded. Why is that a production bug, and how would you fix the readiness probe? (See Part 3.)

---

## Part 2: Break down the request flow (Flow B)

Ollama returns per-stage timings. Compare them with client wall-clock time to find **queue** time:

Script: [`../load-testing/breakdown.sh`](../load-testing/breakdown.sh) (kept in one place so the copy here can't drift). It prints one CSV row per request: `req, wall_s, server_total_s, queue_s, prefill_s, decode_s, tok_per_s`.

Run with concurrency 1, 2, 4 and 8 and record the averages:

| Concurrency | Avg queue (s) | Avg prefill (s) | Avg decode (s) | Tokens/s per request |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |
| 4 | | | | |
| 8 | | | | |

Then **change one thing at a time** and explain the result:
1. A **long prompt** (paste ~1,500 words): which stage grows? (Expect prefill.)
2. Change `num_predict` from 128 to 512: which stage grows? (Expect decode.)
3. Set `OLLAMA_NUM_PARALLEL=1` vs `4` in the Deployment env: what happens to queue time and per-request tokens/s at concurrency 4?

---

## Part 3: Fix readiness so it means "model loaded"

Create a **separate** Deployment, `ollama-scale`, so the main one stays untouched. It pulls its model at startup and is only Ready once the model is present. That's the "readiness gate after model loading" pattern.

`../manifests/04-ollama-scale.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ollama-scale
  namespace: ai-lab
spec:
  replicas: 1
  selector:
    matchLabels: { app: ollama-scale }
  template:
    metadata:
      labels: { app: ollama-scale }
    spec:
      containers:
      - name: ollama
        image: ollama/ollama:latest      # pin the same tag as 03-ollama.yaml
        command: ["/bin/sh", "-c"]
        args:
        - ollama serve & sleep 3 && ollama pull qwen2.5:0.5b && wait
        env:
        - { name: OLLAMA_HOST,   value: "0.0.0.0:11434" }
        - { name: OLLAMA_MODELS, value: /models }
        ports: [{ containerPort: 11434, name: http }]
        volumeMounts: [{ name: models, mountPath: /models }]
        resources:
          requests: { cpu: 500m, memory: 1Gi }
          limits:   { cpu: "1",  memory: 2Gi }
        readinessProbe:                  # Ready only when the model is on disk and the server answers
          exec:
            command: ["/bin/sh", "-c", "ollama list | grep -q 'qwen2.5:0.5b'"]
          periodSeconds: 5
          failureThreshold: 60
      volumes:
      - name: models
        emptyDir: {}                     # deliberate: every new replica must download weights
---
apiVersion: v1
kind: Service
metadata:
  name: ollama-scale
  namespace: ai-lab
spec:
  selector: { app: ollama-scale }
  ports: [{ name: http, port: 11434, targetPort: http }]
```

```bash
kubectl apply -f manifests/04-ollama-scale.yaml
kubectl -n ai-lab get pod -l app=ollama-scale -w   # Running 0/1 until the model is pulled, then 1/1
```

---

## Part 4: Watch scale-out delay and quota limits

```bash
# Manual scale-out: time from command to Ready
date; kubectl -n ai-lab scale deploy/ollama-scale --replicas=2
kubectl -n ai-lab get pod -l app=ollama-scale -w      # note when the new pod goes 1/1

# Try a third replica. With the Lab 02 quota (limits.memory 8Gi; ollama 4Gi + 2 x 2Gi = 8Gi) it should fail
kubectl -n ai-lab scale deploy/ollama-scale --replicas=3
kubectl -n ai-lab describe rs -l app=ollama-scale | grep -i -A2 "exceeded quota"
```

Optional HPA (K3s ships metrics-server):
```bash
kubectl -n ai-lab scale deploy/ollama-scale --replicas=1
kubectl -n ai-lab autoscale deploy/ollama-scale --cpu-percent=70 --min=1 --max=3
# generate load against the ollama-scale Service (breakdown.sh with URL changed, concurrency 8, in a loop)
kubectl -n ai-lab get hpa -w
```

Record:

| Event | Time |
|---|---|
| Scale command / HPA decision | |
| New pod Scheduled | |
| New pod Running (0/1) | |
| New pod Ready (1/1), model loaded | |
| **Scale-out delay** | |
| What happened at replica 3? | |

---

## Part 5: Write-up (portfolio and interview)

Create `incidents/006-scale-out-delay.md` using `incidents/TEMPLATE.md`:
- **Symptom:** latency kept rising during a load spike even though the HPA scaled out.
- **Diagnosis:** the new replica needed **N seconds** to download and load the model; the third replica was blocked by **ResourceQuota**.
- **Root cause:** autoscaling on CPU reacts too late for slow-starting AI workloads, and capacity limits weren't planned.
- **Prevention:** a readiness gate after model load, pre-pulled weights on a shared PVC or in the image, higher minimum replicas or headroom, scaling on queue depth (KEDA), and a quota sized for peak load.

**Done when:** both timing tables are filled in, the readiness probe has been fixed and tested, scale-out delay has been measured, and INC-006 is written.

## Cleanup
```bash
kubectl -n ai-lab delete hpa ollama-scale --ignore-not-found
kubectl -n ai-lab delete -f manifests/04-ollama-scale.yaml
```
