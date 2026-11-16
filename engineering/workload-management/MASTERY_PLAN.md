# Workload Management Mastery — K8s / OpenShift / HPC / AI (Infra Layer)

Nov 16, 2026 · Nookireddi Dileep · Module index: [README.md](README.md)

> **Status:** this is a plan, not a record of completed work. Labs are ticked only when their write-up and evidence exist in this repo.

## 1. The core model

Kubernetes, OpenShift, HPC and AI clusters all solve the same problem: **match demand (pods, jobs, ranks) to supply (CPU, memory, GPUs, network, storage) under policy (quota, priority, fairness, topology)**. They differ in the unit of work, how strict placement must be, and what failure costs.

Master the shared problem once, then learn each platform's vocabulary for it. My edge: RHEL depth + real HPC/InfiniBand experience + K8s/OpenShift in progress. Few engineers have both the HPC and the cloud-native half — this plan is built to make that combination visible.

**How to use this doc**

- Work layer by layer (sections 3–8). Each layer has *concepts to own* and *labs to do*.
- Every lab ends with a write-up: OpenShift work in [openshift-lab-records](https://github.com/NookireddiDileep/openshift-lab-records), GPU/AI and scheduling work here in AROHAN (`labs/` for runnable labs, [topics/](topics/) for topic notes). Each covers goal, setup, what broke, root cause, fix, commands.
- Tick labs off as you go; section 10 says what order to do them in.

## 2. How the four worlds differ

|  | Kubernetes | OpenShift | HPC (Slurm/PBS) | AI training / inference |
| --- | --- | --- | --- | --- |
| Unit of work | Pod | Pod + SCCs, operators, Routes | Batch job (MPI ranks) | Distributed job (PyTorch DDP/FSDP) or inference service |
| Default scheduling | Pod-at-a-time, best effort | Same scheduler, stricter defaults | All-or-nothing allocation, queues, fair-share, backfill | Gang scheduling + GPU/network topology awareness |
| Lifetime | Long-running services | Same | Hours–days, then exits | Training: days–weeks. Inference: always-on, latency-bound |
| Failure model | Restart; stateless | Same | Requeue; restart from checkpoint | One bad GPU/link stalls the whole job |
| Typical bottleneck | API server, etcd, CNI | Same + operator/upgrade health | Interconnect, parallel FS | GPU interconnect (NVLink, IB/RoCE), storage I/O, power |

**Convergence to watch:** Kubernetes is gaining HPC traits (Kueue, Volcano, topology-aware scheduling, Dynamic Resource Allocation for GPUs), and Slurm is moving onto Kubernetes (SchedMD Slinky). Engineers who speak both languages are the bridge.

## 3. Layer 1 — Node / OS (my strength: go deeper)

**Concepts to own**

- cgroups v2: how pod `requests`/`limits` become `cpu.max`, `cpu.weight`, `memory.max`; QoS classes (Guaranteed/Burstable/BestEffort)
- CFS throttling and why CPU limits hurt latency-sensitive and HPC workloads
- NUMA, hugepages, CPU pinning; kubelet CPU Manager (`static`), Memory Manager, Topology Manager (`single-numa-node`)
- Container runtime internals: CRI-O, runc, namespaces, seccomp/SELinux
- OpenShift node config: MachineConfig, MachineConfigPool, Node Tuning Operator / PerformanceProfile, tuned
- Kernel tuning for HPC/AI: IRQ affinity, THP, `isolcpus`, kdump on nodes

**Labs**

- [ ] Run a pod with CPU limit 500m under load; find its cgroup on the node and read `cpu.stat` throttling counters
- [ ] Enable CPU Manager static policy; prove a Guaranteed pod gets exclusive cores (`taskset`, `/sys/fs/cgroup/.../cpuset.cpus`)
- [ ] Configure hugepages on a worker and consume them from a pod
- [ ] OpenShift: apply a MachineConfig (e.g., a sysctl or kernel arg), watch the MCP roll; break it and recover a degraded MCP
- [ ] Force a memory-pressure eviction; read kubelet logs and node conditions to explain it
- [ ] Debug a node with `oc debug node/…` + `chroot /host`: CRI-O logs, `crictl ps`, `crictl inspect`

## 4. Layer 2 — Accelerators / GPU

**Concepts to own**

- Device plugin model vs Dynamic Resource Allocation (DRA) — DRA is where GPU scheduling is heading
- NVIDIA GPU Operator components: driver, container toolkit, device plugin, DCGM exporter, GPU Feature Discovery, MIG manager
- GPU sharing: MIG (hardware partitions) vs time-slicing vs MPS — isolation and performance trade-offs
- Topology: PCIe switches, NVLink/NVSwitch, GPU↔NIC↔CPU socket affinity (`nvidia-smi topo -m`)
- Health: XID errors, ECC errors, thermal/power throttling, GPU fall-off-the-bus

**Labs** (one rented cloud GPU is enough for most)

- [ ] Install the GPU Operator on a single-GPU node; run a CUDA sample pod
- [ ] Configure time-slicing to advertise 4 replicas of one GPU; schedule 4 pods; observe contention
- [ ] Scrape DCGM exporter metrics into Prometheus; graph utilization vs allocation
- [ ] Read `nvidia-smi topo -m` on a multi-GPU cloud instance and write down which GPU pairs talk over NVLink vs PCIe
- [ ] Study-only (no hardware needed): read the DRA docs and map a ResourceClaim to the old `nvidia.com/gpu: 1` model

## 5. Layer 3 — Network (incl. RDMA / InfiniBand)

**Concepts to own**

- Pod networking basics: CNI, Services, kube-proxy vs eBPF, DNS, NetworkPolicy
- OpenShift: OVN-Kubernetes, Routes/Ingress, egress IPs, `ovnkube-trace`
- Secondary networks: Multus, NetworkAttachmentDefinition, SR-IOV Network Operator, macvlan/ipvlan
- HPC/AI fabric: InfiniBand vs RoCEv2, RDMA, GPUDirect RDMA, NVIDIA Network Operator, rail-optimized topologies
- NCCL basics: what `NCCL_DEBUG=INFO` shows, `NCCL_SOCKET_IFNAME`, `NCCL_IB_HCA`; MTU and PFC/ECN for RoCE

My IBA certification and ADE cluster build are directly relevant here — most K8s engineers have never touched IB.

**Labs**

- [ ] Trace a packet from pod → Service → pod on OVN-K (`ovnkube-trace`, `ovn-nbctl`); write up the path
- [ ] Break DNS (scale CoreDNS/dns-default to 0 or block with NetworkPolicy); diagnose from a pod
- [ ] Install Multus (vanilla K8s) and attach a second macvlan interface to a pod
- [ ] Write a NetworkPolicy that blocks cross-namespace traffic; prove and then debug it
- [ ] Study: a 2-node NCCL all-reduce test (`nccl-tests`) — what output looks like when IB works vs falls back to TCP

## 6. Layer 4 — Storage

**Concepts to own**

- CSI, PV/PVC, StorageClass, access modes (RWO/RWX), volume binding mode `WaitForFirstConsumer`
- OpenShift Data Foundation (Ceph/Rook): OSDs, pools, health
- Parallel filesystems for HPC/AI: Lustre, GPFS (Storage Scale), WEKA — metadata vs data servers, striping
- AI I/O patterns: many small reads for data loading; huge bursty writes for checkpoints
- Local NVMe caching and why data locality matters for GPU utilization

**Labs**

- [ ] Deploy a CSI driver (e.g., local-path or NFS CSI); create StorageClasses with different binding modes and explain the scheduling difference
- [ ] Make a PVC stay Pending (wrong StorageClass, zone mismatch); diagnose from events
- [ ] Run `fio` in a pod against two storage backends; compare IOPS/throughput/latency
- [ ] Simulate a checkpoint: write 20–50 GB from a pod and observe node and storage metrics

## 7. Layer 5 — Scheduling & queueing (the heart of workload management)

**Concepts to own**

- kube-scheduler internals: scheduling framework, filter/score plugins, scheduling profiles, preemption, PriorityClass
- Placement controls: node affinity, pod (anti-)affinity, taints/tolerations, topology spread constraints
- Multi-tenancy: ResourceQuota, LimitRange, namespaces/projects, ClusterResourceQuota (OpenShift)
- Batch on K8s: **Kueue** (ClusterQueue, LocalQueue, ResourceFlavor, cohorts, borrowing, fair sharing, gang admission) and **Volcano** (PodGroup, queues)
- Training operators: Kubeflow Training Operator / JobSet for PyTorch/MPI jobs
- Slurm: partitions, QoS, fair-share, backfill, `sinfo`/`squeue`/`sacct`/`scontrol`; Slurm-on-K8s (Slinky)
- Strategy: bin-packing (GPU clusters, avoid fragmentation) vs spreading (HA services)

**Concept map — Slurm ↔ Kubernetes batch**

| Slurm | Kubernetes / Kueue |
| --- | --- |
| Partition | ClusterQueue + ResourceFlavor |
| Account / fair-share | Cohort + fair sharing |
| QoS / priority | PriorityClass / WorkloadPriorityClass |
| Job allocation (all nodes or none) | Gang admission / PodGroup |
| Backfill | Kueue's queueing strategies (BestEffortFIFO) |
| `scontrol hold` | Suspend a Job / Workload |

**Labs** (all work CPU-only). Bin-packing, gang deadlock and KAI queues are already designed in [Lab 03: GPU scheduling](../../labs/03-gpu-scheduling/README.md); theory in the [scheduling deep dive](../gpu-scheduling/KUBERNETES_SCHEDULING_DEEP_DIVE.md).

- [ ] Write a custom scheduler profile that bin-packs (`MostAllocated`); compare pod placement with the default
- [ ] PriorityClasses: fill the cluster with low-priority pods, submit a high-priority one, observe preemption
- [ ] Install Kueue; create two teams' LocalQueues sharing a cohort; show borrowing and reclaim
- [ ] Gang scheduling: submit a 4-pod job to a cluster that fits only 3; show plain K8s deadlocks partially, Kueue/Volcano admits all-or-nothing
- [ ] Build a 2-node Slurm cluster in VMs; run an MPI hello world; configure fair-share between two accounts
- [ ] Stretch: deploy Slinky (Slurm operator) on kind and submit a job through it

## 8. Layer 6 — Observability & capacity

**Concepts to own**

- Prometheus model (metrics, labels, PromQL), OpenShift monitoring stack, user-workload monitoring
- Key signals: scheduler pending pods and latency, API server latency, etcd fsync/leader changes, node pressure, kube-state-metrics
- GPU truth: allocated vs actually busy (DCGM `DCGM_FI_DEV_GPU_UTIL`, SM occupancy, memory bandwidth)
- Capacity planning: requests vs real usage, overcommit ratios, queue wait time as a capacity signal, chargeback/showback
- Logs and events: `oc adm must-gather`, `oc adm inspect`, event retention

**Labs**

- [ ] Write PromQL for: pods Pending > 5 min; namespace CPU requests vs usage; node memory pressure
- [ ] Build a Grafana/OpenShift dashboard: cluster capacity, requested vs used, Kueue queue depth
- [ ] Run `must-gather` on a lab cluster and find one real warning in it
- [ ] Write a one-page capacity report for your lab cluster: headroom, waste, recommendation

## 9. Troubleshooting drill library

Top troubleshooters work layer by layer and form a hypothesis before reading logs. Break each one on purpose, then fix it and write it up.

| Symptom | Likely layers | First checks |
| --- | --- | --- |
| Pod stuck Pending | Scheduling, quota, storage | `describe pod` events, ResourceQuota, Kueue admission, taints/affinity, PVC binding |
| CrashLoopBackOff | App, config, security | `logs --previous`, exit code, SCC/securityContext, mounted secrets |
| Node NotReady | Node/OS, network | kubelet/CRI-O logs, disk/memory pressure, certificate expiry, kernel panic (kdump) |
| MCP degraded (OpenShift) | Node config | `oc get mcp`, machine-config-daemon logs, rendered config diff |
| Distributed job hangs at start | Scheduling, network | Did every rank schedule? (gang), NCCL interface, MTU, firewall |
| Training slower than benchmark | Node, GPU, storage | NUMA/PCIe placement, CPU throttling, GPU clocks/throttling, data-loader I/O |
| Service unreachable | Network | Endpoints empty? NetworkPolicy, DNS, Route/Ingress, OVN trace |
| etcd slow / API timeouts | Control plane, storage | etcd fsync latency, disk, defrag, leader changes |
| GPU disappears from node | GPU, OS | `nvidia-smi`, dmesg XID errors, operator pod status, driver mismatch after upgrade |

Carry the RHEL boot-lab habit up to cluster level: one break-and-fix per week, documented.

## 10. Phased timeline (0–12 months)

| Phase | Window | Focus | Done when |
| --- | --- | --- | --- |
| 1 — OpenShift platform depth | Months 0–3 | Layers 1, 3, 5 on OpenShift: node config, OVN, scheduler, upgrades, must-gather; CKA + EX280 | CKA + EX280 passed; 10+ lab write-ups public in `openshift-lab-records` |
| 2 — Batch & GPU on K8s | Months 3–6 | Kueue/Volcano (CPU-only), GPU Operator + time-slicing on one cloud GPU, DCGM monitoring | Multi-tenant queue demo with quotas, preemption and a dashboard |
| 3 — Bridge HPC and cloud-native | Months 6–12 | Slurm refresh, Slinky, Multus/SR-IOV, NCCL basics, parallel-FS concepts | Project AROHAN AI capstone: multi-tenant GPU queue + monitoring + a documented failure drill |
| Ongoing | Always | Weekly break-and-fix drill, read upstream KEPs/release notes for scheduling and DRA | A public library of real troubleshooting cases |

Rule of thumb: during Phase 1, anything outside OpenShift platform depth goes to the backlog.

## 11. Lab environment & evidence

**Environment**

- **Free / local:** kind or k3d multi-node clusters for scheduler, Kueue, Volcano, NetworkPolicy and Multus labs; VMs for a 2-node Slurm cluster
- **OpenShift:** trainer-provided lab access, OpenShift Local (CRC) for single-node practice, Red Hat Developer Sandbox for quick checks
- **GPU:** rent one cloud GPU by the hour only for Layer 2 labs; script the setup so each session is short; shut it down after
- **Existing:** reuse the GCP account from the RHEL boot lab for VMs

**Evidence format** (one Markdown file per lab)

1. Goal and layer
2. Environment (versions)
3. What I broke / what went wrong
4. How I diagnosed it (commands + output snippets)
5. Root cause
6. Fix and how I verified it
7. What I'd monitor in production to catch it early

This turns every lab into interview material: "tell me about a time you troubleshot…" answers itself.
