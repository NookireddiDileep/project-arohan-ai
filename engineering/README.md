# Project AROHAN AI — Engineering

Deep-dive notes and study modules behind the labs. The labs in [`labs/`](../labs/) prove things hands-on; this folder explains the theory they test.

How work is approached and judged: [principles](../standards/ENGINEERING_PRINCIPLES.md) · [standards](../standards/README.md). Where the project is going: [ROADMAP.md](../ROADMAP.md). What exists today: the status table in the [README](../README.md).

## Contents

| Area | What it covers | Used by |
|---|---|---|
| [Linux internals](linux-internals/README.md) | The base layer: processes, memory and OOM, files and /proc, tracing, cgroups and namespaces, systemd, networking, 12 production RCAs, 60 rapid-fire Q&As | All labs |
| [Kernel troubleshooting & RCA mastery](kernel-troubleshooting/README.md) | 14-phase roadmap for kernel-level troubleshooting and RCA: hangs and syscall tracing, CPU, interrupts, memory, IO, network, eBPF, vmcore analysis, OpenShift node internals, GPU/HPC kernel layer | All labs |
| [OpenShift vs Kubernetes architecture](platform/OPENSHIFT_VS_KUBERNETES.md) | Layer-by-layer comparison, operators/CVO, RHCOS + MCO, SCCs, Routes, kubectl vs oc, what changes for GPU and inference workloads | All labs |
| [Monolith vs microservices: the operator's view](platform/MONOLITH_VS_MICROSERVICES_OPS.md) | Operational cost of each shape, tail-latency math, myths vs reality, when to split, modular monolith, strangler-fig migration, operator's checklist | All labs |
| [From GPU cluster to GPU cloud service on OpenShift](platform/GPU_CLOUD_SERVICE_ON_OPENSHIFT.md) | Tenancy models, GPU SKUs (full, MIG, time-slice), Kueue quota and metering, governance, sovereignty, day-2 operations, Red Hat + Rafay reference architecture | Labs 04–05 |
| [eBPF for platform engineers](platform/EBPF_FOR_PLATFORM_ENGINEERS.md) | How eBPF works (verifier, JIT, hooks, maps, BTF/CO-RE), Cilium vs kube-proxy vs OVN-Kubernetes, Hubble and OpenShift Network Observability, Falco vs Tetragon vs RHACS, limits and risks | Lab 06 |
| [Kubernetes scheduling deep dive](gpu-scheduling/KUBERNETES_SCHEDULING_DEEP_DIVE.md) | kube-scheduler to GPU gangs: filter/score, fragmentation, gang deadlock, KAI | [Lab 03](../labs/03-gpu-scheduling/README.md) |
| [GPU cluster orchestration: the big picture](gpu-scheduling/GPU_CLUSTER_ORCHESTRATION_OVERVIEW.md) | One-page map with an original layer diagram: Kubernetes vs Slurm control planes, GPU node, fabric, storage, health loop; lifecycle failures mapped to labs; corrections and interview drill | Labs 03–05 |
| [AI inference on Kubernetes](ai-inference/INFERENCE_ON_KUBERNETES.md) | Request lifecycle and where inference latency goes | [Lab 02](../labs/02-ai-inference-reliability/README.md) |
| [Workload management mastery](workload-management/README.md) | K8s / OpenShift / HPC / AI workload management from the infra layer up; topic notes twice a week | All labs |
| [HPC & AI infrastructure mastery](hpc-ai-infrastructure/README.md) | Hands-on ops track for Tier 3 HPC & AI Factory roles: Slurm, BCM, InfiniBand/RDMA, GPU stack, GPUs on K8s/OpenShift, monitoring and automation | Lab 03 (Phase 5) |
| [AI-infrastructure notes](notes/README.md) | Weekly notes from a 40-topic [curriculum](notes/CURRICULUM.md) | — |
| [NVIDIA AI infrastructure](NVIDIA/README.md) | NVIDIA foundations (NCA-AIIO prep) and GPU platform topics | — |
| [NCA-AIIO ecosystem map](NVIDIA/NCA-AIIO-ECOSYSTEM-MAP.md) | One-page revision map: exam blueprint, end-to-end chain from user request to GPU and back, key comparisons, corrections to first-pass notes, what comes after the certification | — |

## How engineering notes relate to labs

**Theory note → lab runbook → run → evidence → status update**

A note explains a mechanism and makes claims; a lab tests those claims with controlled failures; evidence decides the status. A note never marks a lab as done.
