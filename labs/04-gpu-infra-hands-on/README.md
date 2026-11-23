# AROHAN Lab 04: GPU Infrastructure Hands-On. Ten exercises on real NVIDIA GPUs on GCP

## Status

**LAB 04: PLANNED 🟡 (runbook ready, not yet run)** (theory: [HPC & AI infrastructure mastery, Phases 4–5](../../engineering/hpc-ai-infrastructure/README.md) · [AI-infra curriculum](../../engineering/notes/CURRICULUM.md) · [kernel troubleshooting roadmap, Phase 12](../../engineering/kernel-troubleshooting/ROADMAP.md))

**Project:** AROHAN AI · AI Infrastructure track (GPU stack → GPUs on Kubernetes → serving → operations)
**Platform:** Google Cloud Compute Engine, **Spot VMs** with NVIDIA T4, L4 and (one exercise) A100 GPUs
**Time:** about 40–45 GPU-hours across 10 exercises
**Budget:** about **USD 25–40** (≈ ₹2,500–3,500) if you use Spot VMs and delete everything after each session

> Goal: get real, hands-on evidence for what AI-infrastructure roles ask for — driver and firmware lifecycle, CUDA, DCGM, NCCL, containers, the NVIDIA GPU Operator, time-slicing and MIG, model serving and GPU observability — and practise diagnosing GPU-node failures in RCA format.
>
> **Honesty note:** commands are written from vendor documentation and have **not yet been run end to end**. Package names and image tags change between releases: where a step says *check the docs*, confirm the current value first. The first run is the validation; record differences in `evidence/`.

**What this lab does not repeat:** scheduler theory, bin-packing and gang scheduling are covered with fake GPUs in [Lab 03](../03-gpu-scheduling/README.md). This lab is about the **real device stack** underneath.

---

## Exercise map

| # | Exercise | GPU / VM | Hours | Approx. cost |
|---|---|---|---|---|
| 1 | Provision a GPU VM safely (quota, Spot, budget, teardown) | 1× T4 · `n1-standard-4` | 1 | < $1 |
| 2 | Driver + CUDA stack on RHEL-compatible Linux | 1× T4 | 3 | ~$1 |
| 3 | `nvidia-smi` deep dive and CUDA samples | 1× T4 | 2 | < $1 |
| 4 | DCGM health, diagnostics and metrics | 1× T4 | 3 | ~$1 |
| 5 | Break-fix: kernel update breaks the driver | 1× T4 | 3 | ~$1 |
| 6 | GPUs in containers (NVIDIA Container Toolkit, CDI) | 1× T4 | 2 | < $1 |
| 7 | Multi-GPU topology and NCCL bandwidth | 2× T4 · `n1-standard-8` | 4 | ~$3 |
| 8 | Kubernetes + NVIDIA GPU Operator (driver as a container) | 1× T4 · Ubuntu | 6 | ~$3 |
| 9 | GPU sharing: time-slicing (T4) and MIG (A100) | 1× T4, then 1× A100 | 5 | ~$8–10 |
| 10 | Model serving with Triton, GPU observability and a capstone incident drill | 1× L4 · `g2-standard-8` | 8 | ~$5 |

Costs are Spot estimates (GPU + VM + disk). Spot prices change; check [GPU pricing](https://cloud.google.com/compute/gpus-pricing) and [Spot pricing](https://cloud.google.com/spot-vms/pricing) before each session.

---

## Exercise 1 — Provision a GPU VM safely

**Why it matters:** GPU capacity is expensive and quota-gated. Operators are judged on not leaking cost.

1. Use a **paid** billing account (free-trial accounts can't attach GPUs). Create a budget alert at a small amount (Billing → Budgets & alerts).
2. Request GPU quota: IAM & Admin → Quotas → `GPUS_ALL_REGIONS` ≥ 2 and the regional quota (e.g. `NVIDIA_T4_GPUS`, `PREEMPTIBLE_NVIDIA_T4_GPUS`) ≥ 2 in your chosen region.
3. Find a zone that has T4s:
   ```bash
   gcloud compute accelerator-types list --filter="name=nvidia-tesla-t4" --format="value(zone)"
   ```
4. Create a Spot VM (Rocky Linux 9 = RHEL-compatible, no RHEL licence fee):
   ```bash
   export ZONE=<zone-from-step-3>
   gcloud compute instances create gpu-lab-1 \
     --zone=$ZONE --machine-type=n1-standard-4 \
     --accelerator=type=nvidia-tesla-t4,count=1 \
     --maintenance-policy=TERMINATE \
     --provisioning-model=SPOT --instance-termination-action=STOP \
     --image-family=rocky-linux-9 --image-project=rocky-linux-cloud \
     --boot-disk-size=100GB --labels=lab=arohan-gpu
   ```
5. Confirm the GPU is on the PCI bus before any driver exists:
   ```bash
   lspci | grep -i nvidia
   ```
6. **Teardown discipline** (end of every session):
   ```bash
   gcloud compute instances delete gpu-lab-1 --zone=$ZONE --quiet
   gcloud compute disks list --filter="labels.lab=arohan-gpu"   # nothing should remain
   ```

**Evidence:** quota screenshot, `lspci` output, budget alert configured.

---

## Exercise 2 — Driver + CUDA stack on RHEL-compatible Linux

**Why it matters:** the driver is a kernel module tied to the running kernel; CUDA sits on top. Most GPU-node incidents start in this chain.

1. Prerequisites:
   ```bash
   sudo dnf install -y epel-release
   sudo dnf config-manager --set-enabled crb
   sudo dnf install -y kernel-devel-$(uname -r) kernel-headers gcc make dkms
   ```
2. Add NVIDIA's CUDA repository and install the driver and toolkit (open kernel modules are supported on T4 / Turing and newer — *check the docs for the current package names*):
   ```bash
   sudo dnf config-manager --add-repo \
     https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo
   sudo dnf install -y nvidia-open cuda-toolkit
   sudo reboot
   ```
3. Verify every layer:
   ```bash
   lsmod | grep nvidia                    # nvidia, nvidia_uvm, nvidia_modeset loaded
   cat /proc/driver/nvidia/version        # kernel module version
   modinfo nvidia | grep -E "^version|^license"
   nvidia-smi                             # driver version + max CUDA version supported
   /usr/local/cuda/bin/nvcc --version     # toolkit version
   ```
4. Write down the **compatibility chain**: kernel version → driver version → CUDA version the driver supports (top-right of `nvidia-smi`) → toolkit version. The toolkit must not be newer than the driver supports.

**Evidence:** outputs of step 3 and the compatibility chain in `evidence/ex02-stack.md`.

---

## Exercise 3 — `nvidia-smi` deep dive and CUDA samples

1. Persistence and health:
   ```bash
   sudo systemctl enable --now nvidia-persistenced
   nvidia-smi -q | less                       # full report: ECC, clocks, power, PCIe link, retired pages
   nvidia-smi -q -d ECC,TEMPERATURE,POWER,CLOCK
   nvidia-smi --query-gpu=name,pci.bus_id,pcie.link.gen.current,pcie.link.width.current,ecc.mode.current --format=csv
   ```
2. Live monitoring while something runs:
   ```bash
   nvidia-smi dmon -s pucm      # power, utilisation, clocks, memory every second
   ```
3. Build and run CUDA samples:
   ```bash
   sudo dnf install -y git cmake
   git clone --depth 1 https://github.com/NVIDIA/cuda-samples.git && cd cuda-samples
   # follow the repo README to build; then run:
   ./deviceQuery          # compute capability, memory, PCIe IDs
   ./bandwidthTest        # host↔device and device↔device bandwidth
   ```
4. Explain in your notes: what PCIe generation and width the T4 negotiated, and why a downgraded link (e.g. x16 → x8) would hurt training.

**Evidence:** `nvidia-smi -q` excerpt, `deviceQuery` and `bandwidthTest` results.

---

## Exercise 4 — DCGM health, diagnostics and metrics

**Why it matters:** DCGM is how GPU fleets are health-checked before jobs run and monitored while they run.

1. Install DCGM from the CUDA repo (package name includes the DCGM and CUDA major versions — *check the docs*, e.g. `datacenter-gpu-manager-4-cuda12`) and start it:
   ```bash
   sudo dnf install -y datacenter-gpu-manager-4-cuda12
   sudo systemctl enable --now nvidia-dcgm
   dcgmi discovery -l
   ```
2. Diagnostics at increasing depth:
   ```bash
   dcgmi diag -r 1     # quick (seconds)
   dcgmi diag -r 2     # medium
   dcgmi diag -r 3     # long, stresses the GPU (minutes)
   ```
3. Health watches and field monitoring:
   ```bash
   dcgmi health -s a && dcgmi health -c
   dcgmi dmon -e 150,155,203,204,252   # temp, power, GPU util, mem-copy util, framebuffer used
   ```
4. Export metrics: run `dcgm-exporter` (container from NGC, see Exercise 6) and scrape `:9400/metrics`; find `DCGM_FI_DEV_GPU_UTIL` and `DCGM_FI_DEV_XID_ERRORS`.
5. Fill in the **Xid triage table** in the [HPC & AI module, Phase 4](../../engineering/hpc-ai-infrastructure/README.md) from NVIDIA's Xid documentation: meaning and action (restart app / reset GPU / drain node / RMA).

**Evidence:** `dcgmi diag -r 3` report, a metrics excerpt, completed Xid table.

---

## Exercise 5 — Break-fix: a kernel update breaks the driver

**Why it matters:** "GPU node NotReady after patching" is one of the most common real incidents. Patching is a strength from enterprise Linux operations; this connects it to GPUs.

1. Record the working state: `uname -r`, `nvidia-smi`, `dkms status`.
2. Simulate the incident: install a newer kernel **without** matching `kernel-devel`, make it default and reboot.
   ```bash
   sudo dnf install -y kernel --setopt=install_weak_deps=False
   sudo reboot
   ```
3. Observe the symptom and collect evidence:
   ```bash
   nvidia-smi                      # "couldn't communicate with the NVIDIA driver"
   lsmod | grep nvidia             # nothing
   dkms status
   journalctl -k -b | grep -iE "nvidia|nouveau"
   ```
4. Fix it two ways: (a) install `kernel-devel-$(uname -r)` and rebuild (`sudo dkms autoinstall`), then reboot; (b) roll back with `grubby --set-default` to the previous kernel.
5. Write the RCA: trigger (kernel update), root cause (no module built for the new kernel), prevention (kernel and driver pinned together, pre-built/precompiled modules, drain-patch-verify per node).

**Evidence:** `evidence/ex05-rca.md` in the repo's RCA format.

---

## Exercise 6 — GPUs in containers (NVIDIA Container Toolkit, CDI)

1. Install the toolkit and generate a CDI spec:
   ```bash
   curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
     | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
   sudo dnf install -y nvidia-container-toolkit podman
   sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
   nvidia-ctk cdi list
   ```
2. Run a GPU container with Podman (use a CUDA base image whose CUDA version your driver supports — *check NGC for the current tag*):
   ```bash
   podman run --rm --device nvidia.com/gpu=all nvcr.io/nvidia/cuda:<tag>-base-ubi9 nvidia-smi
   ```
3. Show what the container actually received: device nodes (`ls -l /dev/nvidia*` inside the container) and the injected driver libraries.
4. Run `dcgm-exporter` the same way for Exercise 4, step 4.

**Evidence:** container `nvidia-smi` output; one paragraph on how CDI injects devices and libraries.

---

## Exercise 7 — Multi-GPU topology and NCCL bandwidth

**Why it matters:** distributed training lives or dies on GPU-to-GPU bandwidth and NUMA placement.

1. Create a VM with **2× T4** (`n1-standard-8`), repeat Exercise 2 (or reuse a disk image you saved).
2. Topology:
   ```bash
   nvidia-smi topo -m      # PIX / PXB / PHB / NODE / SYS between GPUs and CPUs
   numactl -H
   lscpu | grep -i numa
   ```
3. Install NCCL from the CUDA repo and build `nccl-tests`:
   ```bash
   sudo dnf install -y libnccl libnccl-devel
   git clone --depth 1 https://github.com/NVIDIA/nccl-tests.git && cd nccl-tests
   make CUDA_HOME=/usr/local/cuda
   ./build/all_reduce_perf -b 8 -e 256M -f 2 -g 2
   ```
4. Experiments: rerun with `NCCL_DEBUG=INFO` (read the transport chosen), with `NCCL_P2P_DISABLE=1`, and with `CUDA_VISIBLE_DEVICES=0`. Explain the bus-bandwidth differences.
5. Note the limits: T4s talk over PCIe (no NVLink); DGX/HGX systems use NVLink/NVSwitch inside the node and InfiniBand/RoCE between nodes.

**Evidence:** `topo -m` matrix, `all_reduce_perf` tables for each run, written explanation.

---

## Exercise 8 — Kubernetes + NVIDIA GPU Operator (driver as a container)

**Why it matters:** this is how GPUs are run on Kubernetes and OpenShift: the operator manages driver, toolkit, device plugin, GPU Feature Discovery, DCGM exporter and validators.

1. New Spot VM, 1× T4, **Ubuntu 22.04 or 24.04**, *no* NVIDIA driver installed (the operator's driver container will install it).
2. Single-node Kubernetes (K3s) and Helm:
   ```bash
   curl -sfL https://get.k3s.io | sh -
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
   ```
3. Install the GPU Operator (*check the GPU Operator docs for the K3s containerd settings your version needs*):
   ```bash
   helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update
   helm install gpu-operator nvidia/gpu-operator -n gpu-operator --create-namespace --wait
   kubectl get pods -n gpu-operator -w
   ```
4. Verify:
   ```bash
   kubectl describe node | grep -A8 -i "nvidia.com/gpu"      # capacity + allocatable
   kubectl get node -o json | jq '.items[0].metadata.labels | with_entries(select(.key|startswith("nvidia.com")))'
   ```
   Then run the CUDA `vectoradd` sample pod from the GPU Operator docs with `resources.limits: nvidia.com/gpu: 1`.
5. Failure drills: delete the driver daemonset pod and watch recovery; request 2 GPUs on a 1-GPU node (Pending, `Insufficient nvidia.com/gpu`); cordon the node.

**Evidence:** operator pods Running, node labels, sample pod log, notes on each drill. OpenShift equivalent: the same operator installed from OperatorHub with the Node Feature Discovery operator.

---

## Exercise 9 — GPU sharing: time-slicing (T4) and MIG (A100)

**Part A — time-slicing on the Exercise 8 cluster:**

1. Create a time-slicing config and point the operator's device plugin at it (*see "Time-Slicing GPUs in Kubernetes" in the GPU Operator docs*):
   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: time-slicing-config
     namespace: gpu-operator
   data:
     any: |-
       version: v1
       sharing:
         timeSlicing:
           resources:
           - name: nvidia.com/gpu
             replicas: 4
   ```
   ```bash
   kubectl patch clusterpolicies.nvidia.com/cluster-policy --type merge \
     -p '{"spec":{"devicePlugin":{"config":{"name":"time-slicing-config","default":"any"}}}}'
   ```
2. Confirm the node now advertises 4 GPUs; run 4 GPU pods; watch them share one GPU in `nvidia-smi` and DCGM. Note: no memory or fault isolation.

**Part B — MIG on an A100 (a few hours only):** GCP `a2-highgpu-1g` Spot VM (1× A100 40GB).

1. Enable MIG and inspect profiles:
   ```bash
   sudo nvidia-smi -i 0 -mig 1          # may need a GPU reset / reboot
   nvidia-smi mig -lgip                 # available GPU-instance profiles
   ```
2. Create seven `1g.5gb` instances and list them:
   ```bash
   sudo nvidia-smi mig -cgi 1g.5gb,1g.5gb,1g.5gb,1g.5gb,1g.5gb,1g.5gb,1g.5gb -C
   nvidia-smi -L
   ```
3. Explain time-slicing vs MIG vs MPS: isolation, memory guarantees, use cases.

**Evidence:** node allocatable before/after time-slicing; `nvidia-smi -L` with MIG devices; comparison table.

---

## Exercise 10 — Model serving, GPU observability and a capstone incident drill

1. Spot VM `g2-standard-8` (1× L4), driver + toolkit from Exercises 2 and 6.
2. Serve models with **NVIDIA Triton Inference Server** using the Triton quickstart model repository (*check NGC for the current `<yy.mm>` release tag*):
   ```bash
   git clone --depth 1 https://github.com/triton-inference-server/server.git
   cd server/docs/examples && ./fetch_models.sh
   podman run --rm --device nvidia.com/gpu=all -p 8000:8000 -p 8001:8001 -p 8002:8002 \
     -v ${PWD}/model_repository:/models \
     nvcr.io/nvidia/tritonserver:<yy.mm>-py3 tritonserver --model-repository=/models
   curl -s localhost:8000/v2/health/ready -o /dev/null -w "%{http_code}\n"   # 200 = ready
   ```
3. Load-test with `perf_analyzer` from the Triton SDK image and read Triton's own metrics on `:8002/metrics` (`nv_inference_request_success`, `nv_inference_queue_duration_us`, `nv_gpu_utilization`):
   ```bash
   podman run --rm --net=host nvcr.io/nvidia/tritonserver:<yy.mm>-py3-sdk \
     perf_analyzer -m densenet_onnx --concurrency-range 1:8
   ```
   Correlate throughput and p99 latency with `DCGM_FI_DEV_GPU_UTIL` and framebuffer usage from `dcgm-exporter`. Then try dynamic batching in the model's `config.pbtxt` and compare (theory: [AI inference on Kubernetes](../../engineering/ai-inference/INFERENCE_ON_KUBERNETES.md)).

   *Optional LLM variant:* serve a small open model with vLLM's OpenAI-compatible server (`docker.io/vllm/vllm-openai`, e.g. `--model Qwen/Qwen2.5-0.5B-Instruct`) and measure time-to-first-token.
4. **Capstone drill** — have someone else (or a script) inject one fault without telling you, then find it and write the RCA:
   - driver module unloaded / wrong kernel (Exercise 5)
   - CUDA toolkit newer than the driver supports
   - container started without the GPU device
   - GPU memory exhausted by a second process
   - `nvidia-persistenced` stopped, causing slow first calls

**Evidence:** `perf_analyzer` results before/after dynamic batching, latency vs utilisation chart, capstone RCA in `evidence/`.

---

## Stretch (optional)

- **Cluster-level operations** (Slurm, multi-node NCCL, RDMA, node validation, alerting, IaC, Kueue) continue in [Lab 05](../05-gpu-cluster-operations/README.md).
- **NVIDIA LaunchPad:** apply for free time-limited labs on NVIDIA-hosted hardware (DGX-class systems, NVIDIA AI Enterprise) for what Spot VMs can't provide: NVLink/NVSwitch, Fabric Manager, InfiniBand.

## Design drill (no GPU needed)

Senior and consulting rounds add a whiteboard design question. Practise this one aloud in 30 minutes, then write it up in `evidence/design-drill.md`:

> *"Design an on-prem cluster of 256 GPUs for a regulated bank that wants to train and serve its own models."*

Cover, in order: workloads and SLAs → GPU node choice (HGX/DGX class, GPUs per node) → compute fabric (InfiniBand vs RoCE/Spectrum-X, rail-optimised topology) → storage tiers (parallel filesystem, object store, checkpoint bandwidth) → scheduler (Slurm vs Kubernetes/OpenShift, or both) → multi-tenancy and quotas (MIG, namespaces, queues) → security and compliance (air-gap, data residency) → observability (DCGM, fabric and storage metrics) → day-2 operations (driver/firmware lifecycle, burn-in, Xid-driven drain and RMA) → rack power and cooling at the facility level. End with the three biggest risks and how you'd retire them.

## Interview scenarios each exercise prepares you for

| Likely question | Exercise |
|---|---|
| "After patching, the GPU node is NotReady. Walk me through it." | 5 |
| "How do you know a GPU is healthy before scheduling a job on it?" | 4 |
| "A user's container can't see the GPU. Where do you look?" | 6 |
| "Driver, CUDA toolkit and container image versions — how do they relate?" | 2, 6 |
| "Distributed training is slower than expected. How do you diagnose it?" | 7 |
| "How does the GPU Operator work, and what changes on OpenShift?" | 8 |
| "Time-slicing vs MIG vs MPS: which would you use for inference tenants?" | 9 |
| "How would you monitor and tune an inference service on GPUs?" | 10 |
| "What does Xid 79 mean, and what do you do?" | 4 |
| "Design a GPU cluster for …" | Design drill |



- [ ] Ex 1 quota, budget, teardown proof
- [ ] Ex 2 stack outputs + compatibility chain
- [ ] Ex 3 `nvidia-smi -q`, CUDA samples
- [ ] Ex 4 `dcgmi diag -r 3`, metrics, Xid table
- [ ] Ex 5 RCA
- [ ] Ex 6 container GPU proof + CDI note
- [ ] Ex 7 topology + NCCL results
- [ ] Ex 8 GPU Operator running + drills
- [ ] Ex 9 time-slicing + MIG proof
- [ ] Ex 10 Triton serving metrics + capstone RCA
- [ ] Design drill write-up

Status moves to ✅ only when every box has evidence in `evidence/`.
