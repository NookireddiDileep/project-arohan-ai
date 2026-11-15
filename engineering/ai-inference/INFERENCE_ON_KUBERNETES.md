# AI Inference on Kubernetes: Where the Time Goes

> **Project AROHAN AI · Engineering notes**
> My own notes, written after reading a LinkedIn post (Nov 2026) that described AI inference on Kubernetes as two separate flows. The explanations and examples here are mine.

---

## 1. The core idea: two different flows

People often picture the Kubernetes scheduler "sending a request to a GPU". It doesn't.
Inference on Kubernetes is **two separate flows**, owned by different components and failing in different ways:

| | Flow A: getting the model ready | Flow B: serving a request |
|---|---|---|
| When | Once per replica, **before** traffic | Every request, **after** the pod is Ready |
| Owner | kube-scheduler → kubelet → runtime → inference server | Gateway/Ingress → Service → inference server |
| Steps | Pod created → scheduled to a node with GPU/CPU/RAM → image pulled → model weights loaded into memory → warm-up → readiness probe passes | Request routed to a ready endpoint → prompt tokenized → **prefill** (process the whole prompt) → **decode** (generate tokens one by one) → stream tokens back |
| Measured in | Seconds to minutes | Milliseconds to seconds |

**Key point:** the scheduler places **pods**, not **requests**. Once a pod is placed, the scheduler takes no part in individual requests.

---

## 2. Flow A in detail (deployment path)

1. **Scheduling.** The scheduler filters nodes by resource requests (`nvidia.com/gpu`, CPU, memory), affinity, and taints/tolerations.
   - A GPU only exists as a schedulable resource if the **driver + container toolkit + device plugin** (usually installed by the NVIDIA GPU Operator) are healthy and the node advertises `nvidia.com/gpu`.
   - Classic device-plugin model: one whole GPU per request, with no sharing. Sharing needs time-slicing, MPS, MIG or DRA.
2. **Startup.** Image pull, which is large for inference images, then the server starts.
3. **Model load.** Weights are read from storage (PVC, object store or download) into GPU or CPU memory. The bigger the model, the slower storage and network become as bottlenecks.
4. **Warm-up.** A first request or compile step.
5. **Readiness.** The probe must only pass **after** the model is loaded. Otherwise the Service sends traffic to a pod that can't answer yet.

### Ops lesson
A readiness probe that only checks "process is up" is a production bug for inference servers. Readiness should mean the model is loaded and can answer.

---

## 3. Flow B in detail (request path)

| Stage | What happens | What it affects |
|---|---|---|
| Queue | The request waits for a free slot or batch in the server | Time to first token (TTFT) |
| Tokenize | Text → tokens | Small |
| **Prefill** | The model processes all prompt tokens in parallel and builds the KV cache | **TTFT**; grows with prompt length; compute-bound |
| **Decode** | Generates output tokens one at a time, reusing the KV cache | **Inter-token latency / tokens per second**; memory-bandwidth-bound |
| Stream | Tokens sent back as they're produced | What the user actually sees |

---

## 4. Symptom → where to look first

| Symptom | Which flow | Check first |
|---|---|---|
| Pod stuck **Pending** | A: scheduling | GPU/CPU/memory capacity, `nvidia.com/gpu` advertised?, affinity, taints, ResourceQuota |
| Pod Running but **not Ready** for minutes | A: startup / model load | Image pull time, model download/storage throughput, memory, probe thresholds |
| **Long wait for the first token** | B: queue + prefill | Concurrency/queue depth, prompt length, batching settings |
| **Tokens stream slowly** | B: decode | GPU memory bandwidth, model size/quantization, too many concurrent sequences |
| Scale-out "doesn't help" | A + capacity | New replicas still Pending (no GPU) or still loading weights |

---

## 5. Scaling happens at two levels, and both are slow for AI

1. **Pod autoscaling** (HPA, KEDA): adds replicas.
2. **Node autoscaling** (cluster autoscaler, Karpenter, MachineAutoscaler on OpenShift): adds capacity when replicas are Pending.

For normal web apps, a new replica is Ready in seconds. For inference, a new replica has to:
**wait for GPU capacity → (maybe) wait for a new node → pull a large image → load gigabytes of weights → warm up.**
That can take several minutes, so autoscaling must **scale early**, keep **headroom**, or pre-warm, using signals such as queue depth or concurrency rather than CPU alone.

---

## 6. How this maps to my experience

- **HPC parallel:** like a batch scheduler (Slurm/PBS) placing a job on nodes with the right resources. Placement is a separate step from the work the job then does.
- **Ops habit that carries over:** separate the problem by stage before trying fixes. Is it scheduling, startup, model load, queueing, prefill or decode? Each has different owners, metrics and fixes.
- **Interview line:** *"I break inference latency into deployment time versus request time, and request time into queue, prefill and decode. Then I fix the stage that's actually slow."*

---

## 7. Hands-on

Practised in **[Lab 02: Exercise 02B, Inference latency breakdown](../../labs/02-ai-inference-reliability/exercises/02B-inference-latency-breakdown.md)**:
measure each stage of both flows on K3s, then see scale-out delay and quota limits for real.

## 8. Next topics to study
- GPU scheduling: device plugin vs **DRA**, Kueue quotas
- GPU sharing: time-slicing vs MPS vs MIG
- Inference autoscaling: KEDA on queue depth, KServe/Knative, scale-to-zero trade-offs
