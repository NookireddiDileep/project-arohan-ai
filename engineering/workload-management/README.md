# Workload Management Mastery (infra layer)

How workloads are placed, isolated, queued, observed and recovered across **Kubernetes, OpenShift, HPC and AI** clusters, studied from the infrastructure layer up: node/OS, accelerators, network, storage, scheduling and observability.

All four platforms solve one problem: **match demand (pods, jobs, ranks) to supply (CPU, memory, GPUs, network, storage) under policy (quota, priority, fairness, topology).** This module builds that skill one topic at a time.

- **Plan:** [MASTERY_PLAN.md](MASTERY_PLAN.md) has six layers, lab checklists, a troubleshooting drill library and a 12-month timeline
- **Topics:** [topics/](topics/), with one note per topic added regularly; template in [topics/TEMPLATE.md](topics/TEMPLATE.md)
- **Scope split:** this series owns node/OS, scheduling and multi-tenancy, cluster networking, storage basics and cluster observability. GPU-specific topics (GPU Operator, DCGM, sharing, topology), NCCL/RDMA, training storage, serving and AI FinOps belong to the [AI-infra notes](../notes/CURRICULUM.md), so the two series never cover the same topic.
- **Related in AROHAN:** [Kubernetes scheduling deep dive](../gpu-scheduling/KUBERNETES_SCHEDULING_DEEP_DIVE.md) · [Lab 03: GPU scheduling](../../labs/03-gpu-scheduling/README.md) · [weekly AI-infra notes](../notes/README.md)

## Layers

| # | Layer | Focus |
|---|---|---|
| 1 | Node / OS | cgroups v2, CPU/Memory/Topology Manager, NUMA, hugepages, CRI-O, MachineConfig |
| 2 | Accelerators | GPU Operator, device plugin vs DRA, MIG / time-slicing, GPU topology and health |
| 3 | Network | CNI / OVN-K, Multus, SR-IOV, RDMA, InfiniBand vs RoCE, NCCL |
| 4 | Storage | CSI, ODF/Ceph, parallel filesystems, checkpoint I/O |
| 5 | Scheduling & queueing | kube-scheduler framework, priority/preemption, Kueue, Volcano, Slurm |
| 6 | Observability & capacity | Prometheus, DCGM, scheduler/etcd signals, capacity planning |

## Topic log

Each topic note explains the concept, how it works at the infra layer, how it maps across K8s / OpenShift / HPC / AI, how it fails, and one hands-on exercise. The "Exercise" column says honestly whether it has been run.

| # | Date | Topic | Layer | Exercise |
|---|---|---|---|---|
| 01 | 2026-11-19 | [cgroups v2 and pod QoS: how requests and limits become kernel limits](topics/01-cgroups-v2-pod-qos.md) | 1 Node/OS | ⚪ not run |
| 02 | 2026-11-23 | [CPU throttling (CFS quota) and when to drop CPU limits](topics/02-cpu-throttling-cfs-quota.md) | 1 Node/OS | ⚪ not run |
| 03 | 2026-11-26 | [kube-scheduler framework: filter, score, bind, scheduling profiles](topics/03-kube-scheduler-framework-profiles.md) | 5 Scheduling | ⚪ not run |

## Rules for this module

1. One topic per note, small enough to finish in one sitting.
2. Every note has a **failure mode** section: how this goes wrong in production and how to diagnose it.
3. Claims link to sources (upstream docs, KEPs, vendor docs).
4. An exercise is marked run only when output or evidence exists.
