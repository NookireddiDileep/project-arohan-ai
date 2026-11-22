# Linux Kernel Troubleshooting & RCA — End-to-End Roadmap

> **From experienced Linux operations → Kubernetes/OpenShift platform engineering →
> principal-level systems troubleshooting → AI/HPC infrastructure operations.**
>
> Goal: for any production incident, go from *symptom* → *kernel mechanism* → *evidence* →
> *root cause* → *fix and prevention*, and write an RCA that holds up in front of
> senior engineers and vendor support.

---

## How to use this roadmap

- **14 phases**, each with: goal · what to learn · tools · break-and-fix labs · RCA exit criteria.
- A phase is **done** when you can meet its exit criteria *without notes* and have written at least one RCA from its labs.
- Suggested pace: 2–4 weeks per phase alongside a full-time job (~12–15 months end to end).
- Phases 0–2 are prerequisites. After that, follow the track for your target role (section **Role tracks**).

### Depth levels used below

| Level | Meaning |
|---|---|
| **L1** | Know the concept, can explain it |
| **L2** | Diagnose with standard tools, classify the subsystem |
| **L3** | Prove it: profile, trace, post-mortem, kernel stack evidence |
| **L4** | Explain from kernel source, bisect regressions, write custom tooling |

---

## Phase 0 — Method before tools (RCA mindset)

**Goal:** stop troubleshooting by habit; work by method.

**Learn**
- **USE method** — for every resource: Utilization, Saturation, Errors.
- **RED method** for services — Rate, Errors, Duration.
- Brendan Gregg's **60-second checklist**: `uptime, dmesg -T | tail, vmstat 1, mpstat -P ALL 1, pidstat 1, iostat -xz 1, free -m, sar -n DEV 1, sar -n TCP,ETCP 1, top`.
- Trigger vs **root cause** vs **contributing factors**; 5 Whys; fault-tree thinking.
- Evidence discipline: timestamps, before/after data, reproducibility.
- Anti-patterns: "rebooted, fixed", "it was the network", changing several things at once.

**RCA template (use for every lab)**
```
1. Summary (2 lines)
2. Impact (who/what/how long)
3. Timeline (UTC, evidence-backed)
4. Symptom → hypothesis → evidence (commands + output)
5. Root cause (kernel/system mechanism, not just "component X failed")
6. Contributing factors
7. Fix applied / workaround
8. Prevention (monitoring, config, process)
9. Verification
```

**Exit criteria:** take 3 incidents you have already handled in your career and rewrite them in this template, pushing each "root cause" one layer deeper than you originally did.

---

## Phase 1 — Kernel foundations for troubleshooters (L1→L2)

**Learn**
- User vs kernel space; the 3 entries into the kernel: **syscalls, faults, interrupts**.
- Task model: `task_struct`, processes vs threads (`clone()`), kernel threads `[kworker]`, `[ksoftirqd]`, `[kswapd]`.
- **Process states:** `R, S, D, T, Z, I` — and why `D` inflates load average.
- `/proc` and `/sys` as the kernel's live API.
- Boot chain: firmware → GRUB2 → kernel → initramfs (dracut) → systemd.
- Kernel modules, **taint flags**, kernel command line, `sysctl`.
- Kernel logging: `dmesg`, `journalctl -k`, log levels, `printk` rate limiting.
- RHEL kernel lifecycle: kernel versions per release, errata (RHSA/RHBA), kABI, **kpatch** live patching.

**Tools:** `ps -eo pid,stat,wchan:32,cmd`, `/proc/<pid>/{status,stack,maps,fd,limits}`, `lsmod`, `modinfo`, `sysctl -a`, `grubby`, `dracut`, `journalctl`.

**Labs**
- Break boot: bad kernel arg, missing initramfs module, broken fstab → recover from rescue/emergency target.
- Load an out-of-tree module, read `/proc/sys/kernel/tainted`, decode the bits.

**Exit criteria:** explain what the kernel does from power-on to login prompt, and decode any process state and taint value.

---

## Phase 2 — Process hangs & syscall tracing (L2→L3)

**Learn**
- How syscalls work (libc wrapper → `syscall` instruction → syscall table → return / `-errno`), vDSO.
- **strace** deeply: `-p -f -tt -T -e trace= -c -y -k -ff -o`; its ptrace overhead and production risk.
- What strace *can't* show: where a `D`-state task is stuck inside the kernel.
- Alternatives: `/proc/<pid>/stack`, `/proc/<pid>/wchan`, `/proc/<pid>/syscall`, `echo w > /proc/sysrq-trigger`, `hung_task` detector, `perf trace`, `ltrace`, `gdb` attach, `gcore`, core dumps via `systemd-coredump` / `coredumpctl`.

**Labs**
- **NFS hang:** two VMs, block the NFS server with firewall → client process in `D`. Prove it with `/proc/<pid>/stack` (`rpc_wait_bit_killable`), sysrq-w, `nfsstat -c`, `/proc/self/mountstats`, `tcpdump port 2049`. Compare `hard` vs `soft` mounts, `timeo`, `retrans`.
- Debug "app fails with no error" using `strace -f -e trace=file,network`.
- Generate a core dump from a crashing binary, get a backtrace with `gdb`.

**Exit criteria:** for any hung process, state in under 5 minutes which syscall, which kernel function, and which subsystem it is waiting on — with evidence.

---

## Phase 3 — CPU & scheduler (L3)

**Learn**
- Scheduling classes: `deadline`, `rt`, `fair`, `idle`; CFS → **EEVDF** (6.6+); nice, priorities, `chrt`.
- Run-queue latency, context switches (voluntary vs involuntary), load average internals.
- CPU affinity, `isolcpus`, `nohz_full`, cpusets; preemption models incl. `PREEMPT_RT`.
- **cgroup CPU control:** `cpu.weight`, `cpu.max`, **CFS bandwidth throttling**.
- VM effects: **steal time**.
- CPU microarchitecture basics for perf: IPC, caches, branch misses, frequency scaling (`cpupower`).
- **perf:** `perf stat`, `perf top`, `perf record -g`, `perf report`, **flame graphs**, on-CPU vs **off-CPU** analysis.

**Tools:** `mpstat`, `pidstat -w`, `vmstat`, `/proc/pressure/cpu`, `perf`, `runqlat`, `offcputime`, `cpudist`.

**Labs**
- CPU-bound pod with low `cpu.max` → measure throttling vs latency.
- Generate a flame graph of a busy process; find the hot function.
- Produce run-queue latency with oversubscription; measure with `runqlat`.

**Exit criteria:** explain why a service is slow at 30 % CPU, prove it with data, and read a flame graph confidently.

---

## Phase 4 — Interrupts, softirqs & timers (L3)

**Learn**
- Hard IRQs vs bottom halves: **softirqs**, tasklets, workqueues, **threaded IRQs**.
- **MSI/MSI-X**, per-queue IRQs, `/proc/irq/<n>/smp_affinity`, `irqbalance`.
- Network receive scaling: **NAPI**, **RSS, RPS, RFS, XPS**, `net.core.netdev_budget`.
- `ksoftirqd` — when it appears and why.
- Timers, `HZ`, tickless kernels; NMI watchdog; **hard vs soft lockups**.

**Tools:** `/proc/interrupts`, `/proc/softirqs`, `mpstat -I ALL`, `ethtool -l/-L/-x`, `/proc/net/softnet_stat`, `perf top` during softirq load, `bpftrace` on `irq:` tracepoints.

**Labs**
- Pin all NIC IRQs to one CPU, generate traffic → single CPU at 100 % `%si`, drops in `softnet_stat`; fix with affinity / RSS / RPS.
- Compare `irqbalance` on vs off.

**Exit criteria:** answer "one CPU is at 100 % softirq and packets drop — why and how do you fix it?" from mechanism to remediation.

---

## Phase 5 — Memory management (L3)

**Learn**
- Virtual memory, page tables, **TLB**, minor vs major faults.
- **Page cache**, dirty pages, writeback (`vm.dirty_ratio`, `dirty_background_ratio`).
- Reclaim: `kswapd`, **direct reclaim**, LRU lists, swap, `vm.swappiness`, compaction.
- **OOM killer:** `oom_score`, `oom_score_adj`, memcg OOM vs global OOM, `panic_on_oom`.
- **Slab** allocator and kernel memory leaks; `slabtop`.
- **NUMA:** locality, `numactl`, `numastat`, automatic NUMA balancing.
- **THP vs HugePages**; overcommit (`vm.overcommit_memory`).
- **PSI** (`/proc/pressure/memory`).

**Tools:** `free`, `vmstat`, `sar -B -r -W`, `/proc/meminfo`, `/proc/<pid>/smaps_rollup`, `slabtop`, `numastat -m`, `memleak` (bcc), `drop_caches` (lab only).

**Labs**
- Trigger global OOM vs cgroup OOM; read and explain the full OOM report in `dmesg`.
- Simulate a slab leak (e.g. dentry growth from millions of files) and identify it.
- Show NUMA-remote memory penalty with `numactl --membind`.

**Exit criteria:** read any OOM log line by line, and distinguish user-space leak, page-cache pressure, slab growth and NUMA imbalance.

---

## Phase 6 — Storage, filesystems & IO path (L3)

**Learn**
- Full IO path: syscall → **VFS** (inode/dentry/file) → filesystem → page cache → **block layer (blk-mq)** → IO scheduler → driver → device.
- XFS/ext4 journaling, `fsync` semantics, barriers.
- IO schedulers (`none`, `mq-deadline`, `bfq`, `kyber`), queue depth, `nr_requests`.
- Device mapper: **LVM, multipath**, failover behaviour, `no_path_retry`, `queue_if_no_path`.
- SAN (FC/iSCSI) and **NFS client internals** (RPC, slot tables, `hard`/`soft`, `actimeo`).
- Filesystem errors: read-only remount, XFS shutdown, `xfs_repair` / `fsck` basics.
- etcd/database latency sensitivity to `fsync`.

**Tools:** `iostat -xz`, `pidstat -d`, `iotop`, `biolatency`, `biosnoop`, `blktrace`/`btt`, `multipath -ll`, `dmsetup`, `fio`, `/proc/self/mountstats`.

**Labs**
- Fail a multipath path and watch IO behaviour; tune `no_path_retry`.
- `fio` fsync test reproducing etcd's disk check; compare disks/schedulers.
- Fill a filesystem's inodes; trigger a read-only remount.

**Exit criteria:** break down IO latency into queue time vs device time, and explain an IO hang from application to HBA.

---

## Phase 7 — Network stack (L3)

**Learn**
- Packet path RX/TX: NIC ring → NAPI → `sk_buff` → netfilter → IP → TCP/UDP → socket → app.
- TCP: states, handshake, **backlog/`somaxconn`**, buffers (`tcp_rmem/wmem`), congestion control, retransmits, `TIME_WAIT`.
- **netfilter / nftables / iptables**, **conntrack** (`nf_conntrack_max`, table full).
- Linux virtual networking: veth, bridges, VLAN, bonding, **Open vSwitch**, network namespaces.
- MTU / fragmentation / PMTU, offloads (GRO/GSO/TSO).

**Tools:** `ss -tanpi`, `nstat`, `netstat -s`, `ip -s link`, `ethtool -S`, `tcpdump`, Wireshark, `conntrack -S`, `dropwatch`/`perf` `skb:kfree_skb`, `tcpretrans`, `tcplife`.

**Labs**
- Exhaust conntrack → find `table full` in `dmesg`, fix and size properly.
- Full accept queue → SYN drops; diagnose with `ss -lnt` and `nstat`.
- MTU mismatch across a tunnel → large transfers hang, small work.

**Exit criteria:** locate where in the stack a packet is dropped, with counters or tracepoints as proof.

---

## Phase 8 — Tracing & eBPF (L3→L4)

**Learn**
- **ftrace:** `function`, `function_graph`, events; `trace-cmd`, `kernelshark`.
- **Tracepoints, kprobes, uprobes**, USDT.
- **eBPF** concepts: verifier, maps, CO-RE/BTF.
- **bcc tools** (`execsnoop, opensnoop, biolatency, runqlat, offcputime, tcpretrans, memleak`).
- **bpftrace** one-liners → short scripts.
- `perf probe`, `perf trace`, `perf sched`.

**Labs**
- Trace every `openat` on a node with bpftrace and find which process hits a missing file.
- Build a latency histogram for a specific syscall.
- Use `function_graph` to see the kernel path of a `read()`.

**Exit criteria:** answer an ad-hoc "which process / which code path / how long" question with a custom one-liner, safely on production.

---

## Phase 9 — Crash, panic & hardware RCA (L3→L4)

**Learn**
- **kdump:** `crashkernel=`, `/etc/kdump.conf`, testing with sysrq-c, vmcore collection.
- **crash utility:** `sys, log, bt, bt -a, ps, foreach bt, kmem -i, files, net, struct, dis, rd`.
- Failure types: **Oops, BUG, panic, soft lockup, hard lockup, RCU stall, hung task, OOM panic**, `panic_on_oops`.
- Reading a call trace: `RIP`, function+offset, tainted modules, `Hardware name`.
- Hardware errors: **MCE**, **EDAC** memory errors, **PCIe AER**, `rasdaemon`, IPMI SEL.
- Working with vendor support: `sos report`, `xsos`, kernel bug searches, matching known errata.

**Labs**
- Configure kdump, crash the VM, analyze the vmcore end to end.
- Load a deliberately buggy test module (lockup / NULL deref) and RCA it from the vmcore.
- Practise reading real public panic traces (bug trackers, mailing lists).

**Exit criteria:** from a vmcore alone, identify the panicking task, call path, and the responsible module or subsystem, and write the RCA.

---

## Phase 10 — Virtualization layer (L2→L3)

**Learn**
- KVM/QEMU basics, virtio devices, paravirtual drivers (VMware `vmxnet3`, `pvscsi`).
- **Steal time**, CPU overcommit, ballooning, NUMA in VMs.
- Guest vs hypervisor evidence: what you can and cannot prove from inside a guest.
- OpenShift Virtualization (KubeVirt) basics.

**Exit criteria:** prove from inside a guest whether slowness is guest-side or hypervisor-side.

---

## Phase 11 — Containers, Kubernetes & OpenShift node internals (L3)

**Learn**
- **Namespaces** (all types), **cgroups v2** in depth (`cpu`, `memory`, `io`, `pids`, `memory.events`, PSI per cgroup).
- Capabilities, **seccomp**, **SELinux** (`container_t`, MCS), overlayfs, user namespaces.
- Runtime path: kubelet → **CRI-O** → runc/crun; `crictl`, conmon.
- **QoS classes → cgroup slices** (Guaranteed / Burstable / BestEffort).
- **OOMKilled vs Evicted**, kubelet eviction thresholds, node pressure conditions.
- **CPU Manager, Memory Manager, Topology Manager**, static CPU pinning.
- OpenShift: RHCOS, **MachineConfig**, **Node Tuning Operator / Tuned**, **PerformanceProfile** (HugePages, isolated CPUs, RT kernel), `oc debug node`, `toolbox`, `must-gather`.
- etcd disk and network sensitivity; API server latency roots on nodes.

**Labs**
- Build a container by hand with `unshare` + cgroup files.
- Reproduce: CPU throttling, memcg OOM, eviction, PID exhaustion, SELinux denial on hostPath, conntrack exhaustion on a node.
- Apply a PerformanceProfile / Tuned profile and verify the kernel result on the node.

**Exit criteria:** for any pod- or node-level symptom, drop from `oc`/`kubectl` to the node, to the cgroup, to the kernel subsystem — and back to a supported fix.

---

## Phase 12 — AI / HPC infrastructure kernel layer (L3 + targeted L4)

**Learn**
- **GPU driver stack:** `nvidia.ko`, `nvidia-uvm`, `nvidia-peermem`, `nvidia-fabricmanager`; kernel ↔ driver version coupling; OpenShift **GPU Operator + Driver Toolkit**.
- GPU health: **Xid errors**, ECC/row remapping, **DCGM** diagnostics and metrics, `nvidia-smi -q`.
- **NVLink / NVSwitch**, **MIG**, MPS, time-slicing.
- **PCIe topology & AER**, `lspci -vvv`, link width/speed degradation.
- **NUMA / CPU / GPU / NIC affinity:** `nvidia-smi topo -m`, `lstopo`, Topology Manager.
- **IOMMU / VFIO**, SR-IOV.
- **RDMA:** InfiniBand, RoCE, verbs, `ibstat`, `ibv_devinfo`, `perfquery`, `rdma` tool; **GPUDirect RDMA / Storage**.
- Distributed training failures: **NCCL** (`NCCL_DEBUG=INFO`), hangs, slow collectives, stragglers.
- HugePages, pinned memory, IO for large datasets (parallel filesystems, NVMe).
- Scheduler integration: Slurm cgroups, Kubernetes device plugins, Kueue / batch scheduling basics.

**Labs** (cloud GPU instance or single-GPU workstation)
- Install GPU Operator on a cluster; break driver/kernel compatibility and recover.
- Collect DCGM diagnostics; map GPU ↔ NUMA ↔ NIC topology.
- Run a multi-GPU NCCL test and interpret bandwidth and debug output.

**Exit criteria:** RCA a "training job slow / hung / GPU fell off the bus" incident across GPU, PCIe, NUMA, network and kernel layers.

---

## Phase 13 — RCA mastery & capstone (L4)

**Learn**
- Reading kernel source purposefully (elixir.bootlin.com): follow a function from a stack trace.
- Kernel regressions: compare versions, changelogs, `git bisect` on a test VM.
- Following LWN.net and kernel mailing lists for subsystems you operate.
- Writing small tools: bpftrace scripts → bcc/libbpf in Python or Go.
- Leading incidents: communication, blameless post-mortems, turning RCAs into monitoring and automation.

**Capstone**
- 10 written RCAs across phases 2–12, each with commands, evidence and prevention.
- One "game day": someone else breaks your lab cluster; you find and RCA it under time pressure.
- A personal troubleshooting runbook / cheat-sheet repository.

---

## Role tracks

| Target role | Required phases | Depth |
|---|---|---|
| **Kubernetes / OpenShift platform engineer** | 0, 1, 2, 3, 5, 6 (NFS/etcd/IO basics), 7 (conntrack/MTU/OVS), **11** | Solid L2, L3 on phase 11 |
| **Senior / principal systems engineer, SRE, large-scale workload troubleshooter** | 0–11, 13 | **L3 everywhere**, L4 in tracing & crash |
| **AI / HPC infrastructure & operations** | Everything above + **12** | L3 + targeted L4 on GPU/PCIe/NUMA/RDMA |

### Typical interview probes per level
- *Platform:* OOMKilled vs Evicted, throttling, SELinux/seccomp denials, node NotReady, etcd latency.
- *Principal systems:* interrupts/softirqs, perf & flame graphs, strace limits and alternatives, D-state RCA, vmcore analysis, TCP backlog/retransmits, NUMA.
- *AI infra:* Xid triage, NCCL hangs, GPU/NIC NUMA affinity, GPUDirect, driver lifecycle on clusters.

---

## Lab environment

| Need | Setup |
|---|---|
| Core kernel labs | 2–3 RHEL 9/10 VMs (free Red Hat developer subscription), kdump enabled |
| NFS / storage | One VM as NFS server, one as client; extra virtual disks for LVM/multipath |
| Kubernetes | kind / K3s / kubeadm cluster on VMs |
| OpenShift | Single-node OpenShift or OpenShift Local (CRC) |
| GPU | Short-lived cloud GPU instances when you reach phase 12 |

---

## Core resources

**Books**
- Brendan Gregg — *Systems Performance*, 2nd ed. (spine of phases 0, 3–7)
- Brendan Gregg — *BPF Performance Tools* (phase 8)
- Robert Love — *Linux Kernel Development* (phase 1 & 13 background)
- *Understanding the Linux Kernel* — Bovet & Cesati (reference)

**Docs & sites**
- Kernel documentation: https://docs.kernel.org (cgroup-v2, PSI, networking, admin-guide)
- Red Hat RHEL docs: *Monitoring and managing system status and performance*, *Managing, monitoring and updating the kernel* (kdump), networking & storage guides
- OpenShift docs: Node Tuning Operator, PerformanceProfile, MachineConfig, GPU Operator
- NVIDIA docs: GPU Operator, DCGM, Xid error catalogue, NCCL
- https://www.brendangregg.com · https://lwn.net · https://elixir.bootlin.com

**Courses / certs (optional)** — Red Hat performance tuning and troubleshooting courses (check current catalogue), CKA/CKS, NVIDIA AI infrastructure certifications.
