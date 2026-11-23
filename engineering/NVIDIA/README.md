# NVIDIA AI Infrastructure

NVIDIA-focused theory behind AROHAN's GPU work: my study notes for the **NVIDIA Certified Associate – AI Infrastructure & Operations (NCA-AIIO)**, which I passed in August 2026 ([verified Credly badge](https://www.credly.com/badges/bdcee063-5fa6-4907-b7b2-99d789e2de33)). For a one-page revision map of the whole exam, see [NCA-AIIO ecosystem map](NCA-AIIO-ECOSYSTEM-MAP.md).

These notes are the theory base. Hands-on GPU work happens in the [labs](../../labs/), and deeper GPU topics are written up in the weekly [AI-infrastructure notes](../notes/README.md).

## What's here

| Module | Covers | Status |
|---|---|---|
| [01 — Essential AI knowledge](Foundations/Module-01-Introduction-to-AI/README.md) | AI/ML/DL basics, training vs inference, the GPU's role | ✅ First pass |
| [02 — AI infrastructure](Foundations/Module-02-AI-Infrastructure/README.md) · [my notes](Foundations/Module-02-AI-Infrastructure/MY_NOTES.md) | GPU and system architecture, networking, storage, data-centre considerations | ✅ First pass |
| [03 — AI operations](Foundations/Module-03-AI-Operations/README.md) · [my notes](Foundations/Module-03-AI-Operations/MY_NOTES.md) | Monitoring, cluster management, scheduling and orchestration of AI workloads | ✅ First pass |
| [Progress](Foundations/Progress.md) | Module tracking and certification result | ✅ NCA-AIIO passed |

## Where the GPU topics go next

| Topic | Where it is covered |
|---|---|
| GPU scheduling, fragmentation, gangs, KAI | [Scheduling deep dive](../gpu-scheduling/KUBERNETES_SCHEDULING_DEEP_DIVE.md) → [Lab 03](../../labs/03-gpu-scheduling/README.md) |
| LLM inference latency and reliability | [Inference notes](../ai-inference/INFERENCE_ON_KUBERNETES.md) → [Lab 02](../../labs/02-ai-inference-reliability/README.md) |
| GPU Operator, DCGM, GPU sharing (MIG / time-slicing / MPS / DRA), topology, XID errors | [AI-infra curriculum](../notes/CURRICULUM.md), Block A |
| NCCL, InfiniBand / RoCE, storage and checkpoints for training | [AI-infra curriculum](../notes/CURRICULUM.md), Block C |
| Serving (vLLM, Triton, KServe, OpenShift AI) | [AI-infra curriculum](../notes/CURRICULUM.md), Block D |
| GPU observability, FinOps, day-2 upgrades | [AI-infra curriculum](../notes/CURRICULUM.md), Block E |

**Honest constraint:** I have no production GPU experience yet. All GPU work in AROHAN runs on CPU-only clusters with simulated GPUs, and is labelled that way.
