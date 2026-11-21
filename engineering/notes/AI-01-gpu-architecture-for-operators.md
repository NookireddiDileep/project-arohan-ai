# AI-01: GPU architecture for operators

> **Project AROHAN AI · Weekly note 01 · Block A (GPU and node fundamentals)**
> Status of the exercise: ⚪ not run. This note is written from public sources, in my own words. No GPU was used and no result here comes from my own measurement.

---

## 1. TL;DR

- A GPU is many small processors (**SMs**) that run the same instructions on many data items at once. It is built for throughput, not for the lowest latency of one task.
- **Tensor Cores** inside each SM do small matrix multiplications very fast. Most AI work is matrix multiplication, so Tensor Core throughput sets the compute ceiling.
- **HBM** (high-bandwidth memory) sits next to the GPU die. Its size decides which model fits. Its **bandwidth** decides how fast the model can run when memory is the limit.
- LLM token generation (decode) reads all model weights for every step, so it is usually limited by memory bandwidth, not by compute. This is why a GPU with the same TFLOPS but more bandwidth can serve faster.
- For operators: GPU memory is not like CPU RAM. It cannot be over-committed, and when it is full, the process fails (out of memory) instead of swapping.

---

## 2. Concept in plain words

A CPU has few strong cores. A GPU has thousands of simple lanes, grouped in blocks. The block is the **Streaming Multiprocessor (SM)**. Each SM has its own registers, a small fast memory shared by its threads, schedulers, CUDA cores and Tensor Cores. Work is split into thousands of threads and spread over all SMs.

```text
          +---------------------------- GPU package ----------------------------+
          |                                                                     |
 HBM  <-> |  memory controllers  <->  L2 cache (shared by all SMs)             |
 stack    |                              ^   ^   ^   ^                          |
 (x5 on   |                              |   |   |   |                          |
 H100)    |     +----+ +----+ +----+ +----+                  ... many SMs ...    |
          |     | SM | | SM | | SM | | SM |                                    |
          |     |    | |    | |    | |    |   each SM:                         |
          |     +----+ +----+ +----+ +----+   - registers + shared memory/L1   |
          |                                    - CUDA cores (general math)      |
          |                                    - Tensor Cores (matrix math)     |
          +---------------------------------------------------------------------+
                    |  NVLink (to other GPUs)        |  PCIe (to CPU, NIC)
```

Three numbers describe a GPU for an operator:

| Number | What it limits | Where it shows up |
|---|---|---|
| **Memory size** (GB of HBM) | Which model, batch size and KV cache fit | CUDA out-of-memory errors, pod restarts |
| **Memory bandwidth** (GB/s or TB/s) | Speed of memory-bound work such as LLM decode | Tokens per second, inter-token latency |
| **Math throughput** (TFLOPS, per data type) | Speed of compute-bound work such as training and prefill | Time per training step, time to first token |

Public reference points, from NVIDIA documents (see Sources): the H100 SXM5 has 132 SMs, 4 Tensor Cores per SM, 80 GB of HBM3 with about 3 TB/s bandwidth, 50 MB L2 cache and fourth-generation NVLink with 900 GB/s total. NVIDIA labels some Hopper figures as preliminary, so check the current data sheet for your exact part. The A100 has 108 SMs; the 80 GB model is documented with up to 2039 GB/s of HBM2 bandwidth.

### The key idea: arithmetic intensity

NVIDIA's performance guide describes a simple model. A function reads data from memory, does math, and writes the result. Memory time is bytes divided by memory bandwidth. Math time is operations divided by math throughput. The two overlap, so the slower one decides the total time.

- **Arithmetic intensity** = operations the algorithm does ÷ bytes it moves.
- **Ops:byte ratio** of the GPU = math throughput ÷ memory bandwidth.
- If intensity is **below** the GPU ratio, the work is **memory-bound**. If it is **above**, it is **compute-bound**.

LLM decode with batch size 1 does about 2 operations for each weight and reads each weight once. With 2-byte weights, intensity is about 1 operation per byte. A modern GPU needs well over 100 operations per byte to be busy. So decode at small batch is deeply memory-bound, and the GPU's math units mostly wait. Batching more requests together raises intensity, which is the main reason serving engines batch requests (see [AI-24 in the curriculum](CURRICULUM.md)).

---

## 3. How it works on Kubernetes / OpenShift

Kubernetes does not know about SMs, HBM or Tensor Cores. It sees one extended resource, normally `nvidia.com/gpu`, advertised by the NVIDIA device plugin. A pod asks for whole GPUs, and the scheduler counts them like integers.

```text
Pod requests nvidia.com/gpu: 1
   -> kube-scheduler picks a node that advertises a free GPU
   -> kubelet + device plugin hand the GPU device to the container
   -> the container sees the GPU through the NVIDIA runtime
   -> inside, CUDA code decides how work maps onto SMs and HBM
```

What this means in practice:

- **Memory is inside the GPU, not in the pod spec.** The pod's `resources.limits.memory` is host RAM. The GPU memory used by the process is not limited by Kubernetes. With whole-GPU allocation, one pod owns all HBM of its GPU. Sharing (time-slicing, MPS, MIG, DRA) changes this and is the topic of AI-08 and AI-09.
- **The GPU model matters for placement.** The same `nvidia.com/gpu: 1` can mean very different hardware. Labels from GPU Feature Discovery (AI-05) let pods choose a product, memory size or MIG profile.
- **Compute and memory are linked by the product.** A pod that needs 80 GB of HBM must land on a GPU with that much memory. The scheduler will not check this by itself; the model server fails after start-up if the memory is too small.
- **On OpenShift,** the NVIDIA GPU Operator is installed from OperatorHub and works with Node Feature Discovery. New GPU nodes normally come from a MachineSet with a GPU instance type. OpenShift AI model-serving workloads request the same `nvidia.com/gpu` resource. Security Context Constraints (SCCs) apply to GPU pods like any other pod; the Operator's own pods carry the privileges they need. See [OpenShift vs Kubernetes](../platform/OPENSHIFT_VS_KUBERNETES.md) for the platform differences.

Scheduling details are not repeated here. Read [Kubernetes scheduling deep dive](../gpu-scheduling/KUBERNETES_SCHEDULING_DEEP_DIVE.md) and the [workload-management series](../workload-management/README.md).

---

## 4. How it fails in operations

| Symptom | Likely causes (check in this order) |
|---|---|
| `CUDA out of memory` at start-up | Model weights plus KV cache larger than HBM; a second process already on the same GPU; wrong GPU product selected |
| OOM after hours of traffic | KV cache grows with concurrent long requests; memory fragmentation in the framework; a leak in the application |
| Low tokens/s though GPU utilization looks high | Memory-bound decode; batch too small; model not quantized; wrong precision (FP32 instead of FP16/BF16) |
| Low GPU utilization, slow training | Input pipeline or storage is the bottleneck; small batch; CPU-side preprocessing; waiting on network or collective operations |
| Pod `Pending` with a GPU request | No free `nvidia.com/gpu`; device plugin not healthy; node labels or taints do not match |
| GPU visible in the node, not in the pod | Container toolkit or runtime problem; pod not requesting the resource (see AI-03) |
| Throughput lower than the spec sheet suggests | Power or thermal throttling; a PCIe-only path where NVLink was expected (AI-02); sparse-versus-dense TFLOPS mix-up in the data sheet |

A common reading error: vendor data sheets often list the highest TFLOPS figure, for example with sparsity or low precision. Real model code usually runs at dense, higher-precision rates. Always compare the same data type and the same "dense or sparse" setting.

---

## 5. How to observe it

On a node or in a pod that has GPU access:

```bash
# Illustrative: summary of GPU model, memory used/total, utilization, power
nvidia-smi

# Fields that matter for this topic, in CSV (script friendly)
nvidia-smi --query-gpu=name,memory.total,memory.used,utilization.gpu,utilization.memory,power.draw,clocks.sm --format=csv

# Per-process memory on the GPU
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv
```

Illustrative output shape (not from a real system; values are placeholders):

```text
name, memory.total [MiB], memory.used [MiB], utilization.gpu [%], ...
<GPU model>, <total>, <used>, <percent>, ...
```

Metrics in Prometheus, from dcgm-exporter (full treatment in AI-06):

| Metric (DCGM field) | Use |
|---|---|
| `DCGM_FI_DEV_FB_USED`, `DCGM_FI_DEV_FB_FREE` | HBM used and free: early warning for out-of-memory |
| `DCGM_FI_DEV_GPU_UTIL` | Fraction of time a kernel was running. It does not say how well the SMs were used |
| `DCGM_FI_DEV_MEM_COPY_UTIL` | Memory-controller activity: a hint of memory-bound work |
| `DCGM_FI_PROF_DRAM_ACTIVE`, `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE` | Profiling fields: how busy memory and Tensor Cores are (availability depends on the GPU and driver; check the DCGM documentation) |
| `DCGM_FI_DEV_POWER_USAGE` | Power draw; useful with throttling signals |

Important: "GPU utilization 100%" only means a kernel was resident. A memory-bound decode loop can show 100% while the Tensor Cores are mostly idle. Pair utilization with the profiling fields and with tokens per second.

---

## 6. Hands-on exercise (CPU-only, offline) ⚪ not run

Goal: build intuition for memory-bound versus compute-bound work with a small calculator. It uses no GPU, no network and only the Python standard library. Files are in [AI-01-gpu-architecture-for-operators/](AI-01-gpu-architecture-for-operators/run.sh):

- `roofline.py`: computes the ops:byte ratio, and an **upper bound** of decode tokens per second per sequence at several batch sizes. All inputs are command-line options.
- `run.sh`: runs it for an 8-billion-parameter model in FP16 and with 4-bit weights.
- `job.yaml`: optional, runs the same script as a Job on K3s or kind.

Steps:

```bash
cd engineering/notes/AI-01-gpu-architecture-for-operators
./run.sh
# Optional, on a CPU-only cluster:
kubectl create configmap ai01-roofline --from-file=roofline.py
kubectl apply -f job.yaml
kubectl logs job/ai01-roofline
```

What to look for:

1. At small batch sizes the regime is `memory-bound`, and tokens per second per sequence do not change with batch size. That means the same weight read serves more sequences for free, so total throughput grows with batch.
2. Past the ops:byte ratio the regime becomes `compute-bound`, and per-sequence speed falls.
3. Changing `--bytes-per-param` from 2 to 0.5 raises the memory-bound limit about four times, because fewer bytes are read per step.
4. Try other inputs (`--tflops`, `--bw-gbs`) from a data sheet to compare GPUs.

Limits of the model, stated honestly: it ignores the KV cache, attention, kernel launch overhead, multi-GPU communication and real efficiency. Real servers reach only a fraction of these bounds. The numbers are a way to reason, not a benchmark. Outputs are not recorded in this repo until I run it and add evidence.

---

## 7. Architect's lens (1,000+ GPUs)

- **Buy bandwidth for inference, compute for training.** Inference at modest batch sizes is memory-bound, so HBM bandwidth and capacity drive cost per token. Large training is compute- and network-bound.
- **Memory capacity sets the shape of the fleet.** If the model plus KV cache needs more than one GPU's HBM, you need tensor parallelism across GPUs, so NVLink topology (AI-02) becomes part of the design, not an afterthought.
- **Quantization is a capacity and bandwidth tool.** Fewer bytes per weight means more model per GPU and more tokens per second, at some accuracy risk (AI-29).
- **Heterogeneous fleets need labels and policy.** Mixed GPU generations in one cluster increase scheduling and quota complexity. Keep pools by product and drive placement with labels.
- **At scale, small inefficiencies multiply.** A 10% throttling problem on 1,000 GPUs is the output of 100 GPUs. Power and thermal telemetry belong in the standard dashboard.
- **Trade-off:** one big GPU generation is simpler to run; waiting for newer hardware delays capacity. The decision is capacity planning, not only speed.

---

## 8. Interview questions

**1. What is an SM, and why should an operator care?**
The Streaming Multiprocessor is the basic compute block of a GPU. It holds CUDA cores, Tensor Cores, registers and shared memory. Operators care because work is spread over SMs: if there are too few parallel threads, SMs sit idle and utilization is poor. Different GPU products have different SM counts, so the same job does not scale the same everywhere.

**2. Why is LLM token generation limited by memory bandwidth?**
Each new token needs the full set of model weights to be read from HBM, but only a few operations are done per weight at small batch size. Arithmetic intensity is far below the GPU's ops:byte ratio, so the time is set by moving bytes, not by math.

**3. A pod shows 100% GPU utilization but throughput is low. What do you check?**
The utilization metric only says a kernel was running. I check batch size and concurrency, the model precision, memory-activity and Tensor Core profiling fields, throttling (power, temperature, clocks) and whether the server is waiting on CPU or storage. I also compare the data type and sparsity setting of the spec sheet with what the workload really uses.

**4. How does Kubernetes limit GPU memory for a pod?**
It does not. The pod's memory limit is host RAM. With the default device plugin, a pod gets whole GPUs and can use all HBM on them. To split memory, use MIG (hardware partitions with their own memory), or software methods like MPS or time-slicing (no memory isolation by default), or DRA-based drivers.

**5. How do you decide whether a model fits on a GPU?**
Weights (parameters × bytes per parameter) plus KV cache (grows with batch size and sequence length) plus runtime overhead must be below HBM size, with margin. If it does not fit, I use quantization, a GPU with more memory, or tensor parallelism across several GPUs.

---

## 9. Related AROHAN work

- [AI inference on Kubernetes: lifecycle and latency](../ai-inference/INFERENCE_ON_KUBERNETES.md): where prefill (compute-bound) and decode (memory-bound) show up in request latency.
- [Kubernetes scheduling deep dive](../gpu-scheduling/KUBERNETES_SCHEDULING_DEEP_DIVE.md): how `nvidia.com/gpu` becomes schedulable.
- [Workload management series](../workload-management/README.md): queues, quotas and placement (not repeated here).
- [NVIDIA AI infrastructure foundations](../NVIDIA/README.md): certification-oriented background.
- [Lab 02: AI inference reliability](../../labs/02-ai-inference-reliability/README.md) and [Lab 03: GPU scheduling](../../labs/03-gpu-scheduling/README.md): planned labs where these ideas are tested.
- Next in the curriculum: AI-02, NVLink, NVSwitch and PCIe topology ([curriculum](CURRICULUM.md)).

---

## 10. Sources

- NVIDIA, "NVIDIA Hopper Architecture In-Depth": https://developer.nvidia.com/blog/nvidia-hopper-architecture-in-depth/ (SM count, HBM3, L2 cache, Tensor Cores per SM, NVLink; NVIDIA marks some figures as preliminary)
- NVIDIA, "GPU Performance Background User's Guide": https://docs.nvidia.com/deeplearning/performance/dl-performance-gpu-background/index.html (arithmetic intensity, ops:byte ratio, A100 figures)
- NVIDIA, "NVIDIA H100 Tensor Core GPU" product page: https://www.nvidia.com/en-us/data-center/h100.html (current data sheet; check exact part)
- NVIDIA GPU Operator on OpenShift: https://docs.nvidia.com/datacenter/cloud-native/openshift/latest/install-gpu-ocp.html
- NVIDIA GPU Operator platform support: https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/25.3/platform-support.html (check the latest version for your cluster)
