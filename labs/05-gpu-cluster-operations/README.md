# AROHAN Lab 05: GPU Cluster Operations. Slurm, multi-node NCCL, RDMA, node validation, alerting and IaC

## Status

**LAB 05: PLANNED 🟡 (runbook ready, not yet run)** (builds on [Lab 04: GPU infrastructure hands-on](../04-gpu-infra-hands-on/README.md); theory: [HPC & AI infrastructure mastery](../../engineering/hpc-ai-infrastructure/README.md) · [workload management mastery](../../engineering/workload-management/README.md))

**Project:** AROHAN AI · AI Infrastructure track (single GPU node → GPU cluster → fleet operations)
**Platform:** Google Cloud Compute Engine. Mostly **CPU Spot VMs**; GPU Spot VMs (1× T4 each) only for Exercises 3–6
**Time:** about 30–35 hours across 9 exercises
**Budget:** about **USD 15–25** (≈ ₹1,500–2,500) with Spot VMs and full teardown after each session

> Goal: practise what AI-infrastructure job descriptions ask for beyond a single GPU node — Slurm GPU scheduling, automated node validation and drain, containers on HPC schedulers, multi-node NCCL, RDMA, GPU fleet alerting, Kubernetes batch queueing, and provisioning the whole thing as code.
>
> **Honesty note:** commands are written from project documentation and have **not yet been run end to end**. Package names, versions and some flags change between releases; steps marked *check the docs* need confirming first. The first run is the validation; record differences in `evidence/`.

**What this lab does not repeat:** the single-node GPU stack (driver, CUDA, DCGM, containers, GPU Operator, MIG) is [Lab 04](../04-gpu-infra-hands-on/README.md); Prometheus alert lifecycle basics are [Lab 01](../01-workload-reliability/README.md); scheduler theory and KAI are [Lab 03](../03-gpu-scheduling/README.md).

---

## Exercise map

| # | Exercise | Machines | Hours | Approx. cost |
|---|---|---|---|---|
| 1 | Provision the lab with Terraform | — | 3 | < $1 |
| 2 | GPU node configuration with Ansible | 1× T4 node | 3 | ~$1 |
| 3 | Slurm cluster with GPU GRES and cgroup isolation | controller (CPU) + 2× T4 nodes | 6 | ~$4 |
| 4 | Automated node validation: DCGM prolog + drain | same | 3 | ~$2 |
| 5 | Containers on Slurm: Enroot + Pyxis | same | 3 | ~$2 |
| 6 | Multi-node NCCL and diagnosing a hang | same | 4 | ~$3 |
| 7 | RDMA basics with Soft-RoCE | 2× CPU VMs | 3 | < $1 |
| 8 | GPU fleet observability and alerting | Lab 04 Ex 8 cluster (1× T4) | 4 | ~$2 |
| 9 | Kubernetes batch queueing with Kueue | `kind` on a CPU VM (simulated GPUs) | 3 | < $1 |

---

## Exercise 1 — Provision the lab with Terraform

**Why it matters:** GPU clusters are built and rebuilt from code; `terraform destroy` is also the most reliable teardown.

1. Install Terraform and authenticate (`gcloud auth application-default login`).
2. Write `main.tf` with a controller VM and GPU worker VMs. Core of a GPU worker:
   ```hcl
   resource "google_compute_instance" "gpu_node" {
     count        = var.gpu_nodes            # 2
     name         = "gpu-node-${count.index + 1}"
     zone         = var.zone
     machine_type = "n1-standard-4"
     labels       = { lab = "arohan-gpu" }

     boot_disk {
       initialize_params {
         image = "rocky-linux-cloud/rocky-linux-9"
         size  = 100
       }
     }
     guest_accelerator {
       type  = "nvidia-tesla-t4"
       count = 1
     }
     scheduling {
       provisioning_model          = "SPOT"
       preemptible                 = true
       automatic_restart           = false
       on_host_maintenance         = "TERMINATE"
       instance_termination_action = "STOP"
     }
     network_interface {
       network = "default"
       access_config {}
     }
   }
   ```
3. Add the controller (`e2-standard-2`, no GPU), a firewall rule allowing all traffic **between lab VMs only** (source tag), and outputs for the IPs.
4. `terraform init && terraform plan && terraform apply`; at the end of every session `terraform destroy`.

**Evidence:** `terraform plan` summary, `terraform destroy` showing zero remaining resources.

---

## Exercise 2 — GPU node configuration with Ansible

**Why it matters:** every GPU node must be identical; drift between driver, CUDA, DCGM and NCCL versions is a top cause of job failures.

1. Inventory from the Terraform outputs (`[controller]`, `[gpu_nodes]`).
2. Write `gpu-node.yml` that turns the manual steps of [Lab 04 Exercises 2, 4 and 6](../04-gpu-infra-hands-on/README.md) into tasks: EPEL/CRB, `kernel-devel` for the running kernel, CUDA repo, driver and toolkit, DCGM, NVIDIA Container Toolkit, NCCL, then reboot and verify. Example task:
   ```yaml
   - name: Add NVIDIA CUDA repository
     ansible.builtin.get_url:
       url: https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo
       dest: /etc/yum.repos.d/cuda-rhel9.repo
   - name: Install driver, CUDA, DCGM, NCCL
     ansible.builtin.dnf:
       name: [nvidia-open, cuda-toolkit, datacenter-gpu-manager-4-cuda12, libnccl, libnccl-devel]
       state: present
   ```
3. Pin versions in `group_vars` and add a final assertion task: `nvidia-smi --query-gpu=driver_version --format=csv,noheader` equals the pinned version on every node.
4. Run it twice and show the second run is idempotent (`changed=0`).

**Evidence:** playbook, first and second run recaps, version-assertion output.

---

## Exercise 3 — Slurm cluster with GPU GRES and cgroup isolation

**Why it matters:** Slurm is the scheduler most AI-infrastructure and HPC job descriptions ask for.

1. On all nodes: install Munge and Slurm (Rocky 9 + EPEL: `munge`, `slurm`, `slurm-slurmctld` on the controller, `slurm-slurmd` on GPU nodes), copy the same `/etc/munge/munge.key` everywhere, start `munge`.
2. `/etc/slurm/slurm.conf` (same file on every node; key lines):
   ```ini
   ClusterName=arohan
   SlurmctldHost=controller
   GresTypes=gpu
   ProctrackType=proctrack/cgroup
   TaskPlugin=task/cgroup,task/affinity
   SelectType=select/cons_tres
   SelectTypeParameters=CR_Core_Memory
   NodeName=gpu-node-[1-2] CPUs=4 RealMemory=14000 Gres=gpu:t4:1 State=UNKNOWN
   PartitionName=gpu Nodes=gpu-node-[1-2] Default=YES MaxTime=INFINITE State=UP
   ```
   (`slurmd -C` on a node prints its real CPU and memory values.)
3. `/etc/slurm/gres.conf` on GPU nodes: `Name=gpu Type=t4 File=/dev/nvidia0`
   `/etc/slurm/cgroup.conf`: `ConstrainCores=yes`, `ConstrainRAMSpace=yes`, `ConstrainDevices=yes`
4. Start `slurmctld` and `slurmd`, then verify:
   ```bash
   sinfo -N -l
   scontrol show node gpu-node-1 | grep -i gres
   srun -p gpu --gres=gpu:1 nvidia-smi -L        # sees one GPU
   srun -p gpu nvidia-smi -L                      # no GPU requested → device hidden by cgroup
   sbatch --gres=gpu:1 --wrap="sleep 120"; squeue
   ```
5. Failure drills: request `--gres=gpu:2` on a 1-GPU node (job pending, read the reason in `squeue`); stop `munge` on one node (node goes DOWN, read `slurmctld` log); set a node DRAIN manually and resume it.
6. Optional: add `slurmdbd` with MariaDB for accounting, then QOS limits and fair-share.

**Evidence:** `sinfo`, both `srun` outputs (proving device isolation), drill notes.

---

## Exercise 4 — Automated node validation: DCGM prolog + drain

**Why it matters:** fleets don't wait for users to find bad GPUs. Nodes are health-checked before jobs and drained automatically on failure.

1. `/etc/slurm/prolog.sh` on GPU nodes (runs as root before each job):
   ```bash
   #!/bin/bash
   # quick GPU health gate before every job
   if ! dcgmi diag -r 1 > /var/log/slurm/prolog-dcgm.log 2>&1; then
     scontrol update nodename="$SLURMD_NODENAME" state=drain reason="prolog: dcgmi diag -r 1 failed"
     exit 1
   fi
   exit 0
   ```
   Add `Prolog=/etc/slurm/prolog.sh` to `slurm.conf` and `scontrol reconfigure`.
2. Simulate a bad node: stop `nvidia-dcgm` or unload the driver on `gpu-node-2` (Lab 04 Exercise 5), submit jobs and watch `gpu-node-2` drain while jobs land on `gpu-node-1`.
3. Recover: fix the node, then `scontrol update nodename=gpu-node-2 state=resume`.
4. Read about the [LBNL Node Health Check](https://github.com/mej/nhc) (`HealthCheckProgram`) for periodic checks between jobs; write how a production pipeline would chain prolog → periodic NHC → drain → ticket → RMA.

**Evidence:** `sinfo -R` showing the drain reason, prolog log, the RCA-style write-up.

---

## Exercise 5 — Containers on Slurm: Enroot + Pyxis

**Why it matters:** HPC and AI clusters run containers through the scheduler; Enroot + Pyxis is NVIDIA's standard on DGX-style Slurm clusters.

1. Install Enroot on GPU nodes from its GitHub releases (*check the README for the current RPMs and GPU hook package*).
2. Build Pyxis (SPANK plugin) against your Slurm version (`slurm-devel` needed) and enable it in `/etc/slurm/plugstack.conf`:
   ```
   required /usr/lib64/slurm/spank_pyxis.so
   ```
3. Run a container through Slurm:
   ```bash
   srun -p gpu --gres=gpu:1 --container-image=nvcr.io#nvidia/cuda:<tag>-base-ubi9 nvidia-smi -L
   ```
4. Compare with Podman/CDI from Lab 04: who pulls the image, where it is unpacked, how the GPU is injected, why HPC prefers unprivileged runtimes.

**Evidence:** containerised `srun` output, comparison notes.

---

## Exercise 6 — Multi-node NCCL and diagnosing a hang

**Why it matters:** distributed training failures usually surface as slow or hung NCCL collectives.

1. On both GPU nodes: Open MPI (`openmpi`, `openmpi-devel`), passwordless SSH between nodes, then build `nccl-tests` with MPI:
   ```bash
   module load mpi/openmpi-x86_64    # or set PATH/LD_LIBRARY_PATH to Open MPI
   make MPI=1 MPI_HOME=$MPI_HOME CUDA_HOME=/usr/local/cuda
   ```
2. Run across nodes (one GPU each, over TCP sockets — no RDMA on these VMs):
   ```bash
   mpirun -np 2 -H gpu-node-1,gpu-node-2 \
     -x NCCL_DEBUG=INFO -x NCCL_SOCKET_IFNAME=eth0 \
     ./build/all_reduce_perf -b 8 -e 128M -f 2 -g 1
   ```
   Compare bus bandwidth with the single-node 2-GPU result from Lab 04 Exercise 7 and explain the gap.
3. Hang drill: during a run, block traffic between the nodes (firewall rule or `iptables` drop on one node). Observe the hang, read `NCCL_DEBUG` output and per-rank state, then set `NCCL_DEBUG_SUBSYS=INIT,NET` and repeat.
4. Optional: launch the same test through Slurm (`srun --mpi=pmix -N2 --gres=gpu:1 …`) if your Slurm build includes PMIx.

**Evidence:** cross-node `all_reduce_perf` table, hang logs, explanation of where NCCL got stuck.

---

## Exercise 7 — RDMA basics with Soft-RoCE

**Why it matters:** InfiniBand and RoCE carry GPU-to-GPU traffic between nodes. Soft-RoCE gives you the real RDMA verbs stack on ordinary VMs.

1. Two CPU VMs on **Ubuntu 22.04/24.04** (its kernel ships the `rdma_rxe` module). Allow UDP 4791 (RoCEv2) between them.
2. On both:
   ```bash
   sudo apt-get install -y rdma-core ibverbs-utils perftest iproute2
   sudo modprobe rdma_rxe
   sudo rdma link add rxe0 type rxe netdev <nic>   # nic name from `ip -br link`
   rdma link
   ibv_devinfo -d rxe0
   ```
3. Bandwidth and latency:
   ```bash
   ib_write_bw -d rxe0                 # on VM A (server)
   ib_write_bw -d rxe0 <VM-A-IP>       # on VM B (client)
   ib_write_lat -d rxe0 / ib_write_lat -d rxe0 <VM-A-IP>
   ```
   Compare with `iperf3` over TCP. Soft-RoCE runs in software, so it will not be faster; the point is the verbs, GIDs, QPs and tools.
4. Map each concept to real fabrics: GID/LID, MTU, PFC/ECN for lossless RoCE, subnet manager and `ibstat`/`perfquery` on InfiniBand, GPUDirect RDMA (`nvidia-peermem`).

**Evidence:** `ibv_devinfo`, `ib_write_bw`/`ib_write_lat` results, concept map.

---

## Exercise 8 — GPU fleet observability and alerting

**Why it matters:** operations teams find thermal throttling, ECC faults and Xid errors from metrics and alerts, not from users.

1. On the [Lab 04 Exercise 8](../04-gpu-infra-hands-on/README.md) cluster: install `kube-prometheus-stack` with Helm and enable the GPU Operator's DCGM exporter ServiceMonitor (*check the GPU Operator docs for the value name*).
2. Import the NVIDIA DCGM Exporter Grafana dashboard; confirm utilisation, memory, temperature and power panels.
3. Write `PrometheusRule` alerts (field names depend on the exporter's counters file — *check it*):
   ```yaml
   - alert: GPUXidError
     expr: DCGM_FI_DEV_XID_ERRORS > 0
     for: 1m
     labels: {severity: critical}
   - alert: GPUHighTemperature
     expr: DCGM_FI_DEV_GPU_TEMP > 85
     for: 5m
     labels: {severity: warning}
   - alert: GPUIdleWhileAllocated
     expr: DCGM_FI_DEV_GPU_UTIL < 5
     for: 30m
     labels: {severity: info}
   ```
   Validate with `promtool check rules`, as in Lab 01.
4. Load the GPU (CUDA sample or Triton from Lab 04) and show each alert's lifecycle; for the idle-GPU alert, explain the cost angle (allocated but unused GPUs).

**Evidence:** dashboard screenshot, rule file, promtool output, alert firing screenshot.

---

## Exercise 9 — Kubernetes batch queueing with Kueue

**Why it matters:** training platforms on Kubernetes need quotas, queues and fair sharing of scarce GPUs.

1. `kind` cluster on a CPU VM with simulated GPUs, exactly as in [Lab 03](../03-gpu-scheduling/README.md) (node status patched to advertise `nvidia.com/gpu`).
2. Install Kueue from its release manifests (*check the Kueue docs for the current version*).
3. Create a `ResourceFlavor`, two `ClusterQueue`s in one cohort (team-a: 4 GPUs, team-b: 4 GPUs, borrowing allowed) and a `LocalQueue` per team namespace.
4. Submit `batch/v1` Jobs labelled `kueue.x-k8s.io/queue-name: <local-queue>` that request `nvidia.com/gpu`. Observe: admission within quota, suspension when over quota, borrowing from the other team, and preemption when the owner reclaims.
5. Compare Kueue (quota and admission) with KAI from Lab 03 (scheduling and gangs) and with Slurm partitions and QOS from Exercise 3.

**Evidence:** `kubectl get workloads -A` over time, ClusterQueue status, comparison table.

---

## Interview scenarios this lab prepares you for

| Likely question | Exercise |
|---|---|
| "How do you schedule GPUs in Slurm, and how do you stop jobs using GPUs they didn't request?" | 3 |
| "How do you keep bad GPU nodes out of the scheduler automatically?" | 4 |
| "How do you run containers on a Slurm cluster?" | 5 |
| "A multi-node training job hangs at start-up. How do you debug it?" | 6 |
| "Explain RDMA, RoCE vs InfiniBand, and what GPUDirect RDMA adds." | 7 |
| "Which GPU metrics would you alert on, and why?" | 8 |
| "How do you share GPUs fairly between teams on Kubernetes?" | 9 |
| "How do you keep driver/CUDA/NCCL versions consistent across a fleet?" | 2 |
| "How do you provision and tear down GPU capacity reproducibly?" | 1 |

## Evidence checklist

- [ ] Ex 1 Terraform plan/apply/destroy
- [ ] Ex 2 Ansible runs (idempotent) + version assertion
- [ ] Ex 3 Slurm GRES + cgroup isolation proof + drills
- [ ] Ex 4 prolog drain + recovery + pipeline write-up
- [ ] Ex 5 Enroot/Pyxis container job
- [ ] Ex 6 cross-node NCCL + hang diagnosis
- [ ] Ex 7 Soft-RoCE results + concept map
- [ ] Ex 8 dashboard + alert rules + firing proof
- [ ] Ex 9 Kueue quota, borrowing and preemption proof

Status moves to ✅ only when every box has evidence in `evidence/`.
