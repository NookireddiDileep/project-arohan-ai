# Project AROHAN AI — Engineering

Deep-dive notes and study modules behind the labs. The labs in [`labs/`](../labs/) prove things hands-on; this folder explains the theory they test.

How work is approached and judged: [principles](../standards/ENGINEERING_PRINCIPLES.md) · [standards](../standards/README.md). Where the project is going: [ROADMAP.md](../ROADMAP.md). What exists today: the status table in the [README](../README.md).

## Contents

| Area | What it covers | Used by |
|---|---|---|
| [Linux internals](linux-internals/README.md) | The base layer: processes, memory and OOM, files and /proc, tracing, cgroups and namespaces, systemd, networking, 12 production RCAs, 60 rapid-fire Q&As | All labs |
| [Kernel troubleshooting & RCA mastery](kernel-troubleshooting/README.md) | 14-phase roadmap for kernel-level troubleshooting and RCA: hangs and syscall tracing, CPU, interrupts, memory, IO, network, eBPF, vmcore analysis, OpenShift node internals, GPU/HPC kernel layer | All labs |
| [OpenShift vs Kubernetes architecture](platform/OPENSHIFT_VS_KUBERNETES.md) | Layer-by-layer comparison, operators/CVO, RHCOS + MCO, SCCs, Routes, kubectl vs oc, what changes for GPU and inference workloads | All labs |
| [Kubernetes scheduling deep dive](gpu-scheduling/KUBERNETES_SCHEDULING_DEEP_DIVE.md) | kube-scheduler to GPU gangs: filter/score, fragmentation, gang deadlock, KAI | [Lab 03](../labs/03-gpu-scheduling/README.md) |
| [AI inference on Kubernetes](ai-inference/INFERENCE_ON_KUBERNETES.md) | Request lifecycle and where inference latency goes | [Lab 02](../labs/02-ai-inference-reliability/README.md) |
| [Workload management mastery](workload-management/README.md) | K8s / OpenShift / HPC / AI workload management from the infra layer up; topic notes twice a week | All labs |
| [HPC & AI infrastructure mastery](hpc-ai-infrastructure/README.md) | Hands-on ops track for Tier 3 HPC & AI Factory roles: Slurm, BCM, InfiniBand/RDMA, GPU stack, GPUs on K8s/OpenShift, monitoring and automation | Lab 03 (Phase 5) |
| [AI-infrastructure notes](notes/README.md) | Weekly notes from a 40-topic [curriculum](notes/CURRICULUM.md) | — |
| [NVIDIA AI infrastructure](NVIDIA/README.md) | NVIDIA foundations (NCA-AIIO prep) and GPU platform topics | — |

## How engineering notes relate to labs

**Theory note → lab runbook → run → evidence → status update**

A note explains a mechanism and makes claims; a lab tests those claims with controlled failures; evidence decides the status. A note never marks a lab as done.
