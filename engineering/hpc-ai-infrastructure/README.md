# HPC & AI Infrastructure Mastery

**Work area: AI Factory and GPU Infrastructure Operations**

A hands-on track toward **Tier 3 HPC & AI infrastructure engineering**: running GPU clusters, Slurm, NVIDIA Base Command Manager (BCM), InfiniBand/RDMA, and GPUs on Kubernetes/OpenShift in production, at the level where you own the hardest incidents.

**Honesty note.** My HPC background is real but dated. At Locuz and Wipro (2012–2016) I worked on HPC cluster implementation and support, including building a 16 TFLOPS cluster and HPC data center from scratch and doing InfiniBand, rack and RAID work. I have **not yet run modern GPU clusters (H100/H200/L40S), BCM or Slurm-on-GPU in production.** This module closes that gap with labs. Lab experience is recorded as lab experience, never as production experience.

- **How it relates to the other series:** the [AI-infra notes](../notes/CURRICULUM.md) and [workload-management module](../workload-management/README.md) explain the *theory*. This module is the *operations lab track*: build, break, fix, write the RCA. Where a phase covers a topic that already has a note, it links to that note instead of repeating it.
- **Priority:** OpenShift comes first. Phases 1–6 start after the OpenShift training track (target: mid-2027). Until then this module is reading only.
- **Evidence rule:** a phase is ✅ only when its lab outputs and RCAs are committed here. See the [status model](../../standards/README.md#status-model).

## What AI Factory and GPU infrastructure operations covers

An AI Factory is a GPU cluster run as a production service for training and inference. Day-2 operations on it span:

| Layer | Typical components | Ops responsibilities |
|---|---|---|
| Compute | GPU nodes (H100/H200/L40S, GB200/GB300 racks), DGX/HGX systems | Driver/firmware lifecycle, GPU health, Xid triage, RMA |
| Fabric | InfiniBand (UFM) or RoCE Ethernet, NVLink/NVSwitch | Link health, error counters, topology, NCCL performance |
| Cluster management | NVIDIA Base Command Manager, Mission Control | Provisioning, images, node lifecycle |
| Workload management | Slurm, Kubernetes/OpenShift + GPU Operator, Run:ai | Queues, quotas, fairshare, GPU allocation |
| Storage | Parallel filesystems, NFS, object storage | Dataset and checkpoint I/O |
| Observability and automation | DCGM, Prometheus/Grafana, Ansible/AWX | Monitoring, alerting, runbooks, automated remediation |

Tier 3 means owning the escalations nobody else could close: root cause across these layers, not just restarts.

## Target role profile

What Tier 3 HPC & AI Factory operations roles typically ask for, and where each item is covered:

| Skill area | Phase |
|---|---|
| HPC cluster administration and Slurm | 1 |
| NVIDIA Base Command Manager (BCM) | 2 |
| InfiniBand networking and RDMA | 3 |
| NVIDIA GPU infrastructure (H100/H200/L40S): driver, CUDA, DCGM, MIG, NVLink, NCCL | 4 |
| Kubernetes and containerized GPU workloads | 5 |
| GPU monitoring, Ansible/AWX automation, production troubleshooting | 6 |
| Linux / RHEL administration | Existing strength |

## Lab environment (no owned GPU hardware)

| Need | How |
|---|---|
| Slurm, BCM, provisioning | GCP VMs (head node + 2–3 compute nodes), torn down after each session |
| RDMA practice | Soft-RoCE (`rdma_rxe`) between two VMs |
| Real GPUs | Short spot/on-demand rentals: L4/T4 for basics, a few hours on a multi-GPU A100/H100 node for MIG, NVLink and NCCL |
| BCM license | NVIDIA's free-to-use BCM license (up to 8 accelerators per node, any cluster size, no enterprise support) |

Every GPU session is scripted (Ansible/Bash) so rented time is spent on the lab, not on setup.

---

## Phase 1: Slurm in depth (~4 weeks, no GPU)

**Build:** munge, `slurmctld`, `slurmd`, `slurmdbd` + MariaDB on 1 head + 3 compute VMs.

- [ ] Partitions, QoS, fairshare, accounting (`sacct`, `sreport`, `sshare`)
- [ ] Reservations, preemption, job arrays, `--exclusive`, dependencies
- [ ] GRES configuration for GPUs in `gres.conf` / `slurm.conf` (syntax now, real GPUs in Phase 4)
- [ ] Node lifecycle: `scontrol update nodename=… state=drain|resume`, health-check program

**Drills (each gets an RCA):**
- [ ] Node stuck DOWN / DRAIN: find the reason, fix, resume
- [ ] Munge authentication failure from clock skew
- [ ] Jobs stuck PENDING: read the Reason codes (`Resources`, `Priority`, `QOSMaxJobsPerUser`, `ReqNodeNotAvail`)
- [ ] `slurmdbd` down: what still works, what is lost, recovery

## Phase 2: NVIDIA Base Command Manager (~3 weeks, no GPU)

**Build:** BCM head node on a VM; PXE-provision compute VMs.

- [ ] Software images, categories, node provisioning states
- [ ] `cmsh` modes: `device`, `category`, `softwareimage`, `partition`; Base View
- [ ] Deploy Slurm via BCM's workload-manager setup
- [ ] Image update and rolling reprovisioning of nodes

**Drills:**
- [ ] Node fails to PXE boot: DHCP/TFTP/provisioning interface
- [ ] Image sync goes wrong on a subset of nodes
- [ ] Node stuck in a provisioning state

## Phase 3: InfiniBand and RDMA (~3 weeks, mostly no hardware)

**Concepts:** subnet manager (OpenSM / UFM), LIDs and GUIDs, fat-tree topology, partitions (P_Keys), HDR/NDR link speeds, InfiniBand vs RoCE. Theory: AI-infra notes 18–19 in the [curriculum](../notes/CURRICULUM.md).

- [ ] Soft-RoCE between two VMs: `ibv_devinfo`, `ib_write_bw` / `ib_read_lat` (perftest)
- [ ] MPI over UCX across the two nodes
- [ ] Diagnostics reference (know cold even where hardware is needed): `ibstat`, `ibstatus`, `iblinkinfo`, `ibdiagnet`, `perfquery`, `mlxlink`, `mst`

**Scenario RCAs:**
- [ ] Link flapping
- [ ] Port stuck in INIT (no subnet manager)
- [ ] Degraded link width / speed
- [ ] Rising symbol / link error counters

## Phase 4: The GPU stack (~4 weeks, rented GPUs)

Theory: AI-infra notes 1–9 in the [curriculum](../notes/CURRICULUM.md).

- [ ] Driver + CUDA + container toolkit install; version-compatibility chain
- [ ] `nvidia-smi` in depth: persistence mode, ECC, clocks, power limits, `topo -m`
- [ ] DCGM: `dcgmi diag` levels 1–3, health checks, field monitoring
- [ ] MIG profiles (A100/H100)
- [ ] NVLink / NVSwitch and Fabric Manager
- [ ] `nccl-tests` (`all_reduce_perf`): bus bandwidth across GPUs
- [ ] Slurm + GPU end to end: GRES, `--gpus-per-task`, GPU binding

**Xid triage table** (fill in from docs and runs): what each means and the action (restart app / reset GPU / drain node / RMA):

| Xid | Meaning | Action |
|---|---|---|
| 13 | | |
| 31 | | |
| 48 | | |
| 63 / 64 | | |
| 74 | | |
| 79 | | |
| 94 / 95 | | |

## Phase 5: GPUs on Kubernetes/OpenShift (~3 weeks, overlaps OpenShift track)

- [ ] NVIDIA GPU Operator: components and install on OpenShift
- [ ] Device plugin, Node Feature Discovery, GPU Feature Discovery labels
- [ ] Time-slicing vs MIG on Kubernetes
- [ ] Network Operator concepts (RDMA for pods)
- [ ] Slurm vs Kubernetes scheduling: where each fits in an AI Factory; Run:ai / KAI concepts. Links to [Lab 03](../../labs/03-gpu-scheduling/README.md)
- [ ] Aligns with AI267 (Red Hat OpenShift AI) in the OpenShift training track

## Phase 6: Operations layer (~3 weeks)

- [ ] dcgm-exporter → Prometheus → Grafana: GPU health, temperature, Xid, ECC dashboards and alerts
- [ ] Ansible / AWX node-lifecycle playbook: drain → diagnose → reboot or reprovision → return to service
- [ ] Runbook library: one runbook per drill from Phases 1–5

---

## Interview readiness checklist

- [ ] Explain a Slurm job's life from `sbatch` to completion, and every reason it can pend
- [ ] Walk through a "GPU fell off the bus" incident end to end
- [ ] Diagnose slow multi-node training: NCCL → IB counters → topology
- [ ] Explain BCM provisioning and how an image change reaches nodes
- [ ] Compare InfiniBand and RoCE for AI clusters
- [ ] Explain GPU Operator components and what breaks when each fails

## Progress

| Phase | Topic | Status |
|---|---|---|
| 1 | Slurm in depth | 🟡 Planned |
| 2 | Base Command Manager | 🟡 Planned |
| 3 | InfiniBand and RDMA | 🟡 Planned |
| 4 | GPU stack | 🟡 Planned |
| 5 | GPUs on Kubernetes/OpenShift | 🟡 Planned |
| 6 | Operations layer | 🟡 Planned |

Total: about 20 weeks part-time, starting after the OpenShift training track.

## Sources

- [Slurm documentation](https://slurm.schedmd.com/documentation.html)
- [NVIDIA Base Command Manager documentation](https://docs.nvidia.com/base-command-manager/)
- [NVIDIA BCM licensing (free-to-use license)](https://docs.nvidia.com/base-command-manager/bcm-licensing-and-support/)
- [NVIDIA DCGM documentation](https://docs.nvidia.com/datacenter/dcgm/latest/)
- [NVIDIA Xid errors](https://docs.nvidia.com/deploy/xid-errors/)
- [NCCL tests](https://github.com/NVIDIA/nccl-tests)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/)
- [Linux RDMA perftest](https://github.com/linux-rdma/perftest)
