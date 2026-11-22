# Linux Kernel Troubleshooting & RCA — End-to-End Roadmap

> **From experienced Linux operations → Kubernetes/OpenShift platform engineering →
> principal-level systems troubleshooting → AI/HPC infrastructure operations.**
>
> Goal: for any production incident, go from *symptom* → *kernel mechanism* → *evidence* →
> *root cause* → *fix and prevention*, and write an RCA that holds up in front of
> senior engineers and vendor support.

---

## How this roadmap fits the rest of AROHAN (no duplication)

This roadmap is the **sequence and the proof**: what to study in which order, which tools, which labs, and when a phase counts as done. It does **not** re-explain concepts that already have a home:

| Already covered in | Used here as |
|---|---|
| [Linux internals notes 01–09](../linux-internals/README.md) | "Read first" for each phase: concepts, basic commands, interview Q&A |
| [Linux internals note 10: depth by role](../linux-internals/10-infrastructure-view-and-depth.md) | The single definition of the **L1–L4 depth scale** and per-area depth by role |
| [Workload management mastery, Layer 1 (Node/OS)](../workload-management/MASTERY_PLAN.md) | Kubernetes/OpenShift node-level topics in Phase 11 |
| [HPC & AI infrastructure mastery](../hpc-ai-infrastructure/README.md) and [AI-infra curriculum](../notes/CURRICULUM.md) | GPU, Slurm, InfiniBand, NCCL and DCGM operations in Phase 12 |

Each phase below therefore has: **Read first** (existing notes) → **Go deeper** (only what isn't covered elsewhere) → **Tools** → **Labs** → **Exit criteria**.

**Done means:** you meet the exit criteria without notes and have written at least one RCA from the phase's labs. Pace: 2–4 weeks per phase alongside a full-time job (~12–15 months end to end). Phases 0–2 are prerequisites; after that follow your [role track](#role-tracks).

Depth levels (L1 Know · L2 Diagnose · L3 Explain · L4 Predict and design) are defined once in [note 10](../linux-internals/10-infrastructure-view-and-depth.md). In this roadmap, **L3 means you can prove the mechanism with evidence** (profiles, traces, kernel stacks, vmcore), and **L4 adds tuning and sizing so it doesn't recur**, going to kernel source when needed.

---

## Phase 0 — Method before tools (RCA mindset)

**Read first:** [08 production scenarios](../linux-internals/08-production-scenarios.md), including "Turning your own experience into stories".

**Go deeper**
- **USE method** (Utilization, Saturation, Errors per resource) and **RED method** (Rate, Errors, Duration per service).
- Brendan Gregg's **60-second checklist**: `uptime`, `dmesg -T | tail`, `vmstat 1`, `mpstat -P ALL 1`, `pidstat 1`, `iostat -xz 1`, `free -m`, `sar -n DEV 1`, `sar -n TCP,ETCP 1`, `top`.
- Trigger vs **root cause** vs **contributing factors**; 5 Whys; fault trees; blameless post-mortems.
- Evidence discipline: UTC timestamps, before/after data, one change at a time, reproduce before you fix.

**RCA template (used for every lab in this roadmap)**
```
1. Summary (2 lines)
2. Impact (who / what / how long)
3. Timeline (UTC, evidence-backed)
4. Symptom → hypothesis → evidence (commands + output)
5. Root cause (the kernel/system mechanism, not just "component X failed")
6. Contributing factors
7. Fix / workaround
8. Prevention (monitoring, config, process)
9. Verification
```

**Exit criteria:** rewrite 3 incidents you have already handled in this template, each pushed one layer deeper than the original diagnosis.

---

## Phase 1 — Kernel foundations for troubleshooters

**Read first:** [01 process lifecycle](../linux-internals/01-process-lifecycle.md) · [03 files, fds and /proc](../linux-internals/03-files-fds-and-proc.md) · [06 systemd, logs and time](../linux-internals/06-systemd-logs-and-time.md)

**Go deeper**
- The 3 entries into the kernel: **syscalls, faults, interrupts**; kernel threads (`kworker`, `ksoftirqd`, `kswapd`) and what their CPU usage tells you.
- Boot chain failure points: GRUB2 → kernel → **initramfs (dracut)** → systemd; rescue/emergency targets.
- Kernel modules, **taint flags**, kernel command line (`grubby`), `sysctl`, `printk` levels and rate limiting.
- RHEL kernel lifecycle: errata (RHSA/RHBA), **kABI**, **kpatch** live patching, why third-party modules (EDR/security agents, storage, GPU) break on kernel updates.

**Tools:** `lsmod`, `modinfo`, `/proc/sys/kernel/tainted`, `grubby`, `dracut`, `journalctl -k -b -1`.

**Labs:** break boot three ways (bad kernel arg, missing initramfs driver, broken fstab) and recover; load an out-of-tree module and decode the taint bits.

**Exit criteria:** explain power-on → login and where each stage can fail; decode any taint value.

---

## Phase 2 — Process hangs & syscall tracing

**Read first:** [04 tracing and debugging](../linux-internals/04-tracing-and-debugging.md) (D state, load average, strace/perf/eBPF basics, decision tree)

**Go deeper**
- Syscall mechanics: libc wrapper → `syscall` instruction → syscall table → `-errno`; vDSO.
- Advanced **strace**: `-p -f -tt -T -e trace= -c -y -k -ff -o`; ptrace overhead and when *not* to use it in production.
- What strace can't show — and the alternatives: `/proc/<pid>/stack`, `/proc/<pid>/wchan`, `/proc/<pid>/syscall`, **sysrq-w** (`echo w > /proc/sysrq-trigger`), `hung_task` detector, **`perf trace`**, `ltrace`, `gdb` attach, `gcore`, `coredumpctl`.
- **NFS client hang mechanics:** RPC waits, `hard` vs `soft`, `timeo`/`retrans`, `/proc/self/mountstats`, `nfsstat -c`.

**Labs**
- **NFS hang:** two VMs, block the server with a firewall rule → client task in `D`. Prove it with `/proc/<pid>/stack` (`rpc_wait_bit_killable`), sysrq-w, `nfsstat -c`, mountstats, `tcpdump port 2049`. Compare `hard` vs `soft`.
- "App fails silently": find the cause with `strace -f -e trace=file,network`, then repeat with `perf trace` and compare overhead.
- Crash a binary, collect the core with `coredumpctl`, backtrace with `gdb`.

**Exit criteria:** for any hung process, state within 5 minutes which syscall, which kernel function and which subsystem it waits on — with evidence — and justify the least intrusive tool for production.

---

## Phase 3 — CPU & scheduler

**Read first:** [01 process states](../linux-internals/01-process-lifecycle.md) · [05 CPU throttling](../linux-internals/05-cgroups-and-namespaces.md) · [08 scenarios S2 and S7](../linux-internals/08-production-scenarios.md)

**Go deeper**
- Scheduling classes (`deadline`, `rt`, `fair`, `idle`), CFS → **EEVDF** (kernel 6.6+, RHEL 10), `chrt`, nice.
- **Run-queue latency**, voluntary vs involuntary context switches, priority inversion.
- Affinity, `isolcpus`, `nohz_full`, cpusets, preemption models incl. `PREEMPT_RT`.
- **Steal time** and CPU overcommit in VMs; frequency scaling (`cpupower`).
- CPU counters: **IPC**, cache and branch misses (`perf stat`).
- **Profiling:** `perf record -g` → **flame graphs**; **on-CPU vs off-CPU** analysis (`offcputime`).

**Tools:** `pidstat -w`, `mpstat`, `/proc/pressure/cpu`, `perf stat/top/record/report`, `runqlat`, `cpudist`, `offcputime`, FlameGraph scripts.

**Labs:** throttled multi-threaded pod (latency vs `nr_throttled`); flame graph of a busy process; oversubscribe a VM and measure `runqlat`.

**Exit criteria:** explain why a service is slow at 30 % CPU, prove it, and read a flame graph aloud.

---

## Phase 4 — Interrupts, softirqs & timers

**Read first:** none in the notes yet — this phase is new ground.

**Go deeper**
- Hard IRQs vs bottom halves: **softirqs**, tasklets, workqueues, **threaded IRQs**.
- **MSI/MSI-X**, per-queue IRQs, `/proc/irq/<n>/smp_affinity`, `irqbalance` (and when to disable it).
- Receive scaling: **NAPI**, **RSS / RPS / RFS / XPS**, `net.core.netdev_budget`, why `ksoftirqd` appears.
- Timers, `HZ`, tickless kernels; NMI watchdog; **soft vs hard lockups**.
- IRQ ↔ NUMA locality for NICs and GPUs.

**Tools:** `/proc/interrupts`, `/proc/softirqs`, `mpstat -I ALL`, `ethtool -l/-L/-x`, `/proc/net/softnet_stat`, `perf top` during softirq load, `bpftrace` on `irq:` tracepoints.

**Labs:** pin all NIC IRQs to one CPU under traffic → one CPU at 100 % `%si` with drops in `softnet_stat`; fix with affinity, RSS and RPS; compare `irqbalance` on/off.

**Exit criteria:** answer "one CPU is at 100 % softirq and packets drop — why, and how do you fix it?" from mechanism to remediation.

---

## Phase 5 — Memory management

**Read first:** [02 memory and OOM](../linux-internals/02-memory-and-oom.md) · [08 scenario S3](../linux-internals/08-production-scenarios.md)

**Go deeper**
- Page tables, **TLB**, minor vs major faults and their cost.
- Dirty pages and writeback (`vm.dirty_ratio`, `dirty_background_ratio`), writeback stalls.
- Reclaim internals: `kswapd` vs **direct reclaim**, LRU lists, compaction, `vm.swappiness`, `min_free_kbytes`.
- Reading a **full OOM report** line by line (`oom_score_adj`, per-zone free, `Mem-Info`, task dump).
- **Slab** growth and kernel memory leaks (`slabtop`, dentry/inode caches).
- **NUMA**: locality, `numastat -m`, automatic NUMA balancing; **PSI** for memory.

**Tools:** `sar -B -r -W`, `/proc/meminfo`, `/proc/<pid>/smaps_rollup`, `/proc/vmstat`, `slabtop`, `numastat`, `numactl`, `memleak` (bcc).

**Labs:** global OOM vs cgroup OOM (explain both reports); create millions of files and find the slab growth; show the remote-NUMA penalty with `numactl --membind`.

**Exit criteria:** distinguish user-space leak, page-cache pressure, slab growth and NUMA imbalance from data alone.

---

## Phase 6 — Storage, filesystems & the IO path

**Read first:** [03 VFS object model](../linux-internals/03-files-fds-and-proc.md) · [04 D state](../linux-internals/04-tracing-and-debugging.md) · [08 scenarios S1, S11](../linux-internals/08-production-scenarios.md)

**Go deeper**
- Full IO path: VFS → filesystem → page cache → **blk-mq** → IO scheduler → driver → device; where latency is added.
- XFS/ext4 journaling, `fsync` semantics, read-only remounts, XFS shutdowns.
- IO schedulers, queue depth, `nr_requests`; NVMe multi-queue.
- **Device mapper**: LVM, **multipath** (`no_path_retry`, `queue_if_no_path`), path failover behaviour.
- SAN (FC/iSCSI) error handling; **etcd and database `fsync` sensitivity**.

**Tools:** `iostat -xz`, `pidstat -d`, `biolatency`, `biosnoop`, `blktrace`/`btt`, `multipath -ll`, `dmsetup`, `fio`.

**Labs:** fail a multipath path under load; run the etcd-style `fio` fsync test across disks/schedulers; exhaust inodes; trigger a read-only remount.

**Exit criteria:** split IO latency into queue time vs device time, and explain an IO hang from application to HBA.

---

## Phase 7 — Network stack

**Read first:** [07 networking and firewall](../linux-internals/07-networking-and-firewall.md) (netfilter, conntrack, TCP states, packet-path order) · [08 scenario S8](../linux-internals/08-production-scenarios.md)

**Go deeper**
- RX/TX path in the kernel: ring → NAPI → `sk_buff` → netfilter → IP → TCP → socket; offloads (GRO/GSO/TSO).
- TCP internals: **accept backlog / `somaxconn`**, SYN queue, buffers (`tcp_rmem/wmem`), congestion control, retransmit timers.
- Virtual networking: veth, bridges, VLAN, bonding, **Open vSwitch**, network namespaces.
- MTU / PMTU discovery failures across tunnels (Geneve/VXLAN).
- **Drop analysis** with tracepoints.

**Tools:** `ss -tanpi`, `nstat`, `ip -s link`, `ethtool -S`, `tcpdump`, `dropwatch` / `perf record -e skb:kfree_skb`, `tcpretrans`, `tcplife`.

**Labs:** full accept queue → SYN drops; MTU mismatch over a tunnel (small requests work, large hang); locate a drop with `skb:kfree_skb`.

**Exit criteria:** locate exactly where in the stack a packet was dropped, with counters or tracepoints as proof.

---

## Phase 8 — Tracing & eBPF

**Read first:** [04 strace, perf, eBPF](../linux-internals/04-tracing-and-debugging.md)

**Go deeper**
- **ftrace**: `function`, `function_graph`, events; `trace-cmd`, `kernelshark`.
- **Tracepoints, kprobes, uprobes**, USDT; overhead and safety in production.
- eBPF internals: verifier, maps, **BTF/CO-RE**.
- **bcc** toolkit end to end; **bpftrace** one-liners → short scripts; `perf probe`, `perf sched`.

**Labs:** find which process opens a missing file node-wide; histogram a syscall's latency; `function_graph` the kernel path of a `read()`.

**Exit criteria:** answer any ad-hoc "which process / which code path / how long" question with a custom one-liner, safely on a production node.

---

## Phase 9 — Crash, panic & hardware RCA

**Read first:** [08 scenario S12 (unexpected reboot)](../linux-internals/08-production-scenarios.md)

**Go deeper**
- **kdump**: `crashkernel=`, `/etc/kdump.conf`, targets, testing with sysrq-c.
- **crash** utility: `sys`, `log`, `bt`, `bt -a`, `ps`, `foreach bt`, `kmem -i`, `files`, `net`, `struct`, `dis`, `rd`.
- Failure types: **Oops, BUG, panic, soft lockup, hard lockup, RCU stall, hung task, OOM panic**, `panic_on_oops`.
- Reading a call trace: `RIP`, function+offset, tainted modules, hardware line.
- Hardware errors: **MCE**, **EDAC**, **PCIe AER**, `rasdaemon`, IPMI SEL.
- Working with vendor support: `sos report`, `xsos`, matching known errata and KB articles.

**Labs:** configure kdump, crash a VM, analyse the vmcore end to end; load a deliberately buggy test module (lockup / NULL deref) and RCA it from the vmcore; read public panic traces from bug trackers.

**Exit criteria:** from a vmcore alone, name the panicking task, call path and responsible module or subsystem, and write the RCA.

---

## Phase 10 — Virtualization layer

**Go deeper**
- KVM/QEMU basics, virtio and paravirtual drivers (`vmxnet3`, `pvscsi`).
- **Steal time**, CPU/memory overcommit, ballooning, vNUMA.
- What you can and cannot prove from inside a guest; what evidence to request from the hypervisor team.
- OpenShift Virtualization (KubeVirt) basics.

**Exit criteria:** prove from inside a guest whether slowness is guest-side or hypervisor-side, and know exactly what to ask the virtualization team for.

---

## Phase 11 — Container, Kubernetes & OpenShift node internals

**Read first:** [05 cgroups and namespaces](../linux-internals/05-cgroups-and-namespaces.md) (incl. debugging a container from the node) · [Workload management Layer 1: Node / OS](../workload-management/MASTERY_PLAN.md) (CPU/Memory/Topology Manager, NUMA, HugePages, CRI-O, MachineConfig)

**Go deeper** (kernel evidence for node-level incidents)
- QoS classes → cgroup slices; reading `cpu.stat`, `memory.events`, `memory.stat`, per-cgroup PSI for a specific pod.
- **OOMKilled vs Evicted** at kernel vs kubelet level; eviction thresholds and node pressure.
- Runtime path: kubelet → CRI-O → conmon → runc/crun; `crictl inspect` to the cgroup path.
- seccomp, capabilities and SELinux **denial evidence** (`ausearch -m avc`, `EPERM` in traces).
- OpenShift node RCA workflow: `oc debug node` → `chroot /host`, `toolbox`, `journalctl -u kubelet -u crio`, `sos report`, `must-gather`; tuning only through MachineConfig, Node Tuning Operator and PerformanceProfile.
- etcd and API-server latency traced down to node disk and network.

**Labs:** reproduce CPU throttling, memcg OOM, eviction, PID exhaustion, an SELinux hostPath denial and conntrack exhaustion on a node — RCA each from `oc` down to the kernel and back to a supported fix.

**Exit criteria:** for any pod- or node-level symptom, go from `oc`/`kubectl` → node → cgroup → kernel subsystem and back to a supported fix.

---

## Phase 12 — AI / HPC node kernel layer

**Read first:** [HPC & AI infrastructure mastery](../hpc-ai-infrastructure/README.md) (Slurm, InfiniBand/RDMA, GPU stack, GPUs on Kubernetes/OpenShift) and the [AI-infra curriculum](../notes/CURRICULUM.md) topics on topology, driver chain, DCGM/Xid, NCCL and RDMA. GPU **operations** live there; this phase covers only the **kernel evidence** underneath them.

**Go deeper**
- GPU kernel modules (`nvidia`, `nvidia-uvm`, `nvidia-peermem`) and kernel ↔ driver coupling; driver build per RHCOS kernel (Driver Toolkit) and what breaks on node upgrades.
- GPU faults in the kernel log: **`NVRM: Xid`**, correlated with **PCIe AER**, link width/speed downgrades (`lspci -vvv`), MCE/EDAC.
- **IOMMU / VFIO** and SR-IOV at the kernel level.
- **IRQ, CPU, memory and NIC locality** for GPU nodes (ties Phases 4 and 5 to `nvidia-smi topo -m`, `lstopo`).
- RDMA kernel side: `ib_core`/`mlx5` modules, `rdma` tool, memory pinning, HugePages for RDMA and DPDK.
- Proving whether a slow or hung training job is a **kernel/node** problem (IRQs, NUMA, PCIe, network drops) or an application/NCCL problem.

**Labs** (short-lived cloud GPU instance): break driver ↔ kernel compatibility and recover; map GPU ↔ NUMA ↔ NIC ↔ IRQ placement; inject PCIe/NUMA misplacement and measure the effect.

**Exit criteria:** RCA a "training job slow / hung / GPU fell off the bus" incident across GPU, PCIe, NUMA, network and kernel layers.

---

## Phase 13 — RCA mastery & capstone

**Go deeper**
- Reading kernel source purposefully ([elixir.bootlin.com](https://elixir.bootlin.com)): follow a function from a stack trace.
- Regressions: compare versions and changelogs, `git bisect` on a test VM.
- Follow [LWN.net](https://lwn.net) and subsystem mailing lists for what you operate.
- Small tools: bpftrace scripts → bcc/libbpf (Python or Go).
- Incident leadership: communication, blameless post-mortems, turning RCAs into alerts and automation.

**Capstone**
- 10 written RCAs across Phases 2–12, each with commands, evidence and prevention.
- A game day: someone else breaks your lab cluster; you find it and write the RCA under time pressure.
- A troubleshooting runbook built from your own RCAs.

---

## Role tracks

Per-area depth for each role is defined in [note 10](../linux-internals/10-infrastructure-view-and-depth.md). This table adds which **phases** each role needs:

| Target role | Phases |
|---|---|
| **Kubernetes / OpenShift platform engineer** | 0, 1, 2, 3, 5, 6 (NFS/etcd/IO basics), 7, **11** |
| **Senior / principal systems engineer, SRE, large-scale workload troubleshooter** | 0–11, 13 |
| **AI / HPC infrastructure & operations** | All, including **12** |

### What senior panels probe
- *Platform:* OOMKilled vs Evicted, throttling, SELinux/seccomp denials, node NotReady, etcd latency.
- *Principal systems:* interrupts and softirqs, perf and flame graphs, strace limits and alternatives, D-state RCA, vmcore analysis, TCP backlog and retransmits, NUMA.
- *AI infrastructure:* Xid + AER triage, driver lifecycle on clusters, GPU/NIC/IRQ NUMA locality, kernel vs NCCL fault isolation.

---

## Lab environment

| Need | Setup |
|---|---|
| Core kernel labs | 2–3 RHEL 9/10 VMs (free Red Hat developer subscription), kdump enabled |
| NFS / storage | One NFS server VM, one client; extra virtual disks for LVM/multipath |
| Kubernetes | kind / K3s / kubeadm on VMs |
| OpenShift | Single-node OpenShift or OpenShift Local (CRC) |
| GPU | Short-lived cloud GPU instances, only for Phase 12 |

---

## Core resources

**Books**
- Brendan Gregg — *Systems Performance*, 2nd ed. (Phases 0, 3–7)
- Brendan Gregg — *BPF Performance Tools* (Phase 8)
- Robert Love — *Linux Kernel Development* (background for Phases 1 and 13)

**Docs and sites**
- Kernel documentation: <https://docs.kernel.org> (admin-guide, cgroup-v2, PSI, networking)
- Red Hat RHEL docs: performance monitoring and tuning, kernel management (kdump, kpatch), networking and storage guides
- OpenShift docs: Node Tuning Operator, PerformanceProfile, MachineConfig, GPU Operator
- <https://www.brendangregg.com> · <https://lwn.net> · <https://elixir.bootlin.com>

**Optional courses / certs:** Red Hat performance tuning and troubleshooting courses (check the current catalogue), CKA/CKS, NVIDIA AI infrastructure certifications.
