# 10 — Linux internals from the infrastructure point of view (plain language)

A plain-language map of Linux internals for infrastructure, platform and AI-infrastructure engineers: what each part does, how it breaks in production, and how deep each role needs to go. Each area ends with a **break-it lab** for a throwaway VM.

> Labs are for disposable VMs only. Never run them on shared or production machines.

---

## The one picture

Think of a Linux server as **a busy office building**.

- **The kernel is the building management.** It owns the rooms, power, lifts and doors. Nobody touches these directly.
- **Processes are the workers.** Every program (nginx, a JVM, kubelet, a container) is a worker.
- **System calls are the request counter.** When a worker needs something (read a file, open a connection, get memory), it fills in a form at the counter (`read()`, `connect()`, `mmap()`), and management does it.

Almost every production problem is one of three things: **workers waiting** for something, **a resource running out**, or **management enforcing a rule**.

---

## 1. Processes and scheduling: workers and their turn at the desk

**Plain version:** there are only as many desks as CPU cores. The scheduler gives each worker short turns. A worker is *running*, *waiting for its turn*, or *sleeping* while it waits for disk, network or a lock. A worker in **`D` state (uninterruptible sleep)** is waiting on hardware and can't even be killed, and load average counts it.

> **Scenario:** load average 80 on 16 cores, CPU 90% idle, pods using an NFS volume stuck in `Terminating`.
> **Really:** the NFS server stopped responding; dozens of processes are in `D` state waiting for it. High load, no CPU use.
> **Evidence:** `ps -eo pid,stat,wchan:30,cmd | awk '$2 ~ /D/'` → `wchan` shows `nfs_*`.
> **Fix:** fix the storage path, not the node's CPU.

**Break-it lab:** mount an NFS export, read from it in a loop, then block the server with a firewall rule. Watch `D` states and load average climb while CPU stays idle. Deep-dive: [04](04-tracing-and-debugging.md#sleepers-d-state).

## 2. Memory: desk space, filing shelves and a bouncer

**Plain version:** RAM is desk space. Linux uses spare space as a **filing shelf (page cache)** for recently read files, so `free` shows little "free" memory. That's normal; watch "available". When memory truly runs out, the **OOM killer** throws someone out. In containers each one has its own **memory limit (cgroup)**: go past it and that container is killed even if the node has RAM to spare.

> **Scenario:** a Java pod restarts with `OOMKilled`, exit 137, while the node has 20 GB free.
> **Really:** the cgroup limit is 1 Gi; heap + metaspace + threads + native memory went over it.
> **Fix:** right-size the limit, make the JVM respect container limits (`-XX:MaxRAMPercentage`), watch `container_memory_working_set_bytes`.

**Break-it lab:** create a cgroup v2 with `memory.max=64M` and run `stress --vm 1 --vm-bytes 128M` in it; read the kill in `journalctl -k` and `memory.events`. Deep-dive: [02](02-memory-and-oom.md).

## 3. Files and file descriptors: the library and its borrowed books

**Plain version:** nearly everything is a file. Each file has an **inode** (index card); an open file gives the process a **file descriptor** (borrowed-book ticket). Both are limited.

> **Scenario A:** `df` shows `/var` 100% full, `du` finds only 40 GB.
> **Really:** a huge log was deleted while a process still holds it open; space isn't freed until it's closed.
> **Evidence / fix:** `lsof +L1`; restart or reload the process, or truncate via `/proc/<pid>/fd/<n>`.
>
> **Scenario B:** "No space left on device" with free space in `df -h`. **Really:** inodes exhausted (`df -i`), usually millions of tiny files.
>
> **Scenario C:** `Too many open files`. **Really:** fd limit hit (`ulimit -n`, systemd `LimitNOFILE`) or a descriptor leak (`ls /proc/<pid>/fd | wc -l` keeps growing).

**Break-it lab:** `python3 -c "f=open('/var/tmp/big','w'); import time; time.sleep(9999)" &`, write a large file to it, `rm` it, compare `df` and `du`, find it with `lsof +L1`. Deep-dive: [03](03-files-fds-and-proc.md).

## 4. Disk I/O: the queue at the bank counter

**Plain version:** every write joins a queue. Fast disks clear it quickly; slow or shared storage (a busy virtualisation datastore) makes everyone wait. **iowait** is CPU time spent waiting on that queue.

> **Scenario:** the Kubernetes/OpenShift API turns slow and the etcd leader keeps changing.
> **Really:** etcd must `fsync` every write; control-plane VMs sit on slow shared storage and fsync p99 goes above ~10 ms.
> **Evidence:** `iostat -x 1` (high `await`, `%util`), etcd `wal_fsync_duration` metrics.
> **Fix:** faster, dedicated storage for the control plane. One of the most common real incidents on virtualised clusters.

**Break-it lab:** run `fio` with small synchronous writes (`--fsync=1`) while a second `fio` saturates the same disk; watch latency in `iostat -x 1`.

## 5. Networking: the post office

**Plain version:** a **socket** is a mailbox, a **port** a door number, and **conntrack** the post office's ledger of every open conversation, with a fixed number of pages.

> **Scenario:** random connection timeouts on a busy node, worse at peak, no app errors.
> **Really:** the **conntrack table is full**; new connections are silently dropped (`dmesg`: `nf_conntrack: table full, dropping packet`).
> **Fix:** raise `nf_conntrack_max` through the platform's tuning mechanism, reduce short-lived connections.
>
> **Related:** piles of `CLOSE_WAIT` (`ss -tan state close-wait`) mean the application isn't closing connections: an app bug, not a network one.

**Break-it lab:** lower `net.netfilter.nf_conntrack_max` to a small value on a test VM, generate many connections (`ab`/`hey`), and catch the drops in `dmesg` and `conntrack -S`. Deep-dive: [07](07-networking-and-firewall.md).

## 6. cgroups and namespaces: apartment walls and utility meters

**Plain version:** a container isn't a mini-VM. It's an ordinary process with **namespaces** (walls: it sees only its own processes, network, hostname, mounts) and **cgroups** (meters: caps on CPU, memory, PIDs). Every pod setting becomes one of these.

> **Scenario:** an API pod's p99 latency spikes every few seconds while CPU usage looks low (40% of its limit).
> **Really:** **CPU throttling**. A 500m limit is 50 ms of CPU per 100 ms period; a burst uses it in 30 ms and the process is frozen for the remaining 70 ms.
> **Evidence:** `container_cpu_cfs_throttled_periods_total`, or `nr_throttled` in the cgroup's `cpu.stat`.
> **Fix:** raise or remove the CPU limit (keep the request), or tune the app's thread count.

**Break-it lab:** set `cpu.max = 20000 100000` on a cgroup, run a CPU-bound loop in it, read `cpu.stat`. Then build a "container by hand" with `unshare --pid --net --mount --fork`. Deep-dive: [05](05-cgroups-and-namespaces.md).

## 7. systemd and boot: the building's morning routine

**Plain version:** at boot **systemd** starts services in dependency order. If one critical step fails, the building doesn't open.

> **Scenario:** after patching, a server never comes back; the console shows emergency mode.
> **Really:** a bad `/etc/fstab` entry (e.g. an NFS mount without `nofail`) blocks boot.
> **Fix:** from the console, `journalctl -xb`, fix fstab. On image-based nodes (RHCOS), node config goes through MachineConfigs, so the same mistake shows as a degraded MachineConfigPool.

**Break-it lab:** add a bogus mount to fstab on a VM snapshot, reboot, recover from the console. Deep-dive: [06](06-systemd-logs-and-time.md).

## 8. Seeing inside: the doctor's instruments

| Instrument | Shows |
|---|---|
| `/proc`, `/sys` | Live state of processes and the kernel (`/proc/<pid>/status`, `fd`, `limits`, `cgroup`) |
| `strace` | Every system call a process makes and what it waits on |
| `perf` | Where CPU time actually goes |
| **eBPF** tools (`execsnoop`, `biolatency`, `tcpretrans`, `bpftrace`) | Precise, low-overhead tracing inside the kernel |
| `dmesg` / `journalctl -k` | What the kernel itself complained about (OOM, disk errors, conntrack full) |

Deep-dive: [04](04-tracing-and-debugging.md#spies-strace-perf-ebpf).

---

## How deep should you go? Depth by role

Four depth levels:

| Level | Means | Sounds like |
|---|---|---|
| **L1: Know** | Name it, say what it does | "The OOM killer kills processes when memory runs out." |
| **L2: Diagnose** | Symptom → commands → fix | "Exit 137 with OOMKilled, so compare the limit with working-set memory." |
| **L3: Explain** | The kernel mechanism and trade-offs | "cgroup v2 `memory.max` was hit; the kernel picked a task in that cgroup and sent SIGKILL. Page cache counts toward the limit but is reclaimed first." |
| **L4: Predict and design** | Prevent, tune and size before it breaks | "Requests at p95 usage, no CPU limit, Guaranteed QoS for the latency-critical tier." |

| Area | **Kubernetes / OpenShift admin** | **Platform engineer** | **AI infrastructure / senior troubleshooter** |
|---|---|---|---|
| Processes, states, signals | L3 | L3 | L4 |
| Memory, OOM, page cache | L3 | L4 | L4 (+ hugepages, NUMA) |
| Files, inodes, fds | L3 | L3 | L3 |
| Disk I/O, filesystems | L2 | L3 (etcd, Ceph) | L4 (parallel filesystems, NVMe) |
| Networking, conntrack, sockets | L2 | L3 (overlay networks, MTU, egress) | L4 (RDMA, InfiniBand/RoCE) |
| cgroups, namespaces | L3 | L4 | L4 |
| systemd, boot | L3 | L3 | L3 |
| Tracing (`strace`, `perf`, eBPF) | L2 | L3 | L4 |
| GPU/hardware (PCIe, NUMA, IRQs, drivers) | L1 | L2 | L4 |

**Rule of thumb for interviews:** knowing commands (L2) gets you through an L2 support round. Senior and platform rounds keep asking *"but what is the kernel actually doing?"*. That's L3, and for anyone working with containers, **processes, memory/OOM and cgroups/namespaces must be L3** because every container problem ends there.

---

## How to practise so it sticks

1. **Answer in five layers every time:** definition → kernel mechanism → evidence commands → production impact → fix and prevention (see the [README](README.md)).
2. **Break it on purpose:** run the eight labs above on a throwaway VM and write each one up as a short RCA.
3. **Connect each kernel fact to Kubernetes:** OOM → `OOMKilled`; `D` state → pods stuck Terminating; conntrack → dropped Service traffic; cgroups → requests and limits.
4. **Two questions a day** from the [rapid-fire Q&A](09-rapid-fire-qa.md), answered out loud.
