# Kernel Troubleshooting & RCA Mastery

An end-to-end learning track for **kernel-level troubleshooting and root-cause analysis**: from experienced Linux operations, through Kubernetes/OpenShift platform engineering and principal-level systems troubleshooting, to AI/HPC infrastructure operations.

- **Roadmap:** [ROADMAP.md](ROADMAP.md) has 14 phases (method, kernel foundations, process hangs and syscall tracing, CPU and scheduler, interrupts and softirqs, memory, storage and IO, network stack, tracing and eBPF, crash/panic and hardware RCA, virtualization, container and OpenShift node internals, AI/HPC kernel layer, RCA mastery). Each phase lists what to learn, tools, break-and-fix labs and exit criteria.
- **Role tracks:** which phases and what depth (L1–L4) a platform engineer, a senior/principal systems engineer and an AI/HPC infrastructure engineer need.
- **RCA template:** every lab ends in a written RCA (Phase 0).

## How it relates to the rest of AROHAN

| Note | Relationship |
|---|---|
| [Linux internals](../linux-internals/README.md) | The concept foundation this track builds on. Read it first; this track goes deeper into evidence, tracing and post-mortem analysis. |
| [Workload management mastery](../workload-management/README.md) | Node/OS layer (cgroups, CPU/Topology Manager, NUMA) overlaps with Phase 11 |
| [HPC & AI infrastructure mastery](../hpc-ai-infrastructure/README.md) | GPU, InfiniBand/RDMA and NCCL operations overlap with Phase 12 |

## Status

🟡 Planned. Theory roadmap only; no lab evidence is claimed. Phase notes and RCAs will be added as each phase is worked through.
