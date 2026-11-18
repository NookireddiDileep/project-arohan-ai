# Linux Internals — the foundation under every platform

A deep, production-focused guide for **Linux, SRE, platform and AI-infrastructure engineers**, and for anyone preparing for a senior interview where the panel goes past commands and asks *"what is the kernel actually doing?"*

## Why this is part of AROHAN

Every layer above it is Linux underneath. A container is a process in namespaces and cgroups. A Kubernetes `OOMKilled` is the kernel's cgroup OOM killer. A pod stuck `Terminating` is often a task in `D` state waiting on storage. CPU throttling, hugepages, conntrack limits and fd exhaustion all show up on GPU and inference nodes long before anything GPU-specific does. You can't debug a platform you can't see through, so this guide is the base the [labs](../../labs/) and the other [engineering notes](../README.md) build on.

Inspired by the "Linux has everything Hollywood has" post (zombies, ghosts, orphans, daemons, killers…). Each of those one-liners hides a 20-minute deep-dive question. This guide covers that depth.

## How to answer a deep internals question (the 5-layer answer)

Senior panels (big-tech SRE, GPU and AI-infrastructure companies, enterprise Linux vendors) score you on how many layers you can go down **without being prompted**:

| Layer | What you say | Example: "What is a zombie?" |
|---|---|---|
| 1. Definition | One crisp sentence | A process that has exited but whose exit status hasn't been collected by its parent. |
| 2. Mechanism | Kernel internals | On exit the kernel frees memory/fds but keeps the `task_struct` + PID so the parent can call `wait4()`. Parent gets `SIGCHLD`. |
| 3. Evidence | Commands you'd run | `ps -eo pid,ppid,stat,cmd \| awk '$3 ~ /^Z/'`, check PPID, `/proc/<ppid>/status` SigCgt |
| 4. Production impact | Why it matters | Zombies hold PIDs → `pid_max`/`pids.max` exhaustion → `fork: Resource temporarily unavailable`. |
| 5. Fix + prevention | Ops + design | You can't kill a zombie. Fix/restart the parent; reaping init in containers (tini / `--init`); `SIGCHLD` handler or `SA_NOCLDWAIT`. |

**Rule:** never stop at layer 1. If you only know the command, you sound like L2 support. Layers 2 and 4 are what make you sound senior.

## Hollywood → Kernel map

| Character | Concept | Quick command | Deep-dive |
|---|---|---|---|
| Zombies | Exited, not reaped (`Z`) | `ps -eo pid,ppid,stat,cmd \| awk '$3~/^Z/'` | [01](01-process-lifecycle.md#zombies) |
| Orphans | Parent died → reparented to subreaper / PID 1 | `pstree -p`, `ps -o ppid= -p PID` | [01](01-process-lifecycle.md#orphans-and-subreapers) |
| Parents & children | PID 0 → PID 1 (systemd) + PID 2 (kthreadd) | `ps -o pid,ppid,cmd -p 1,2` | [01](01-process-lifecycle.md#pid-0-pid-1-pid-2) |
| Clones & shapeshifters | `clone()` / `fork()` / `execve()` | `strace -f -e trace=process bash -c 'ls; true'` | [01](01-process-lifecycle.md#fork-clone-exec) |
| Bombs | Fork bomb, PID exhaustion | `cat /sys/fs/cgroup/<cg>/pids.max` | [01](01-process-lifecycle.md#fork-bombs-and-pid-exhaustion) |
| Killers | OOM killer, cgroup OOM, K8s OOMKilled | `journalctl -k \| grep -i -e oom -e "killed process"` | [02](02-memory-and-oom.md) |
| Ghosts | Deleted-but-open files | `lsof +L1` | [03](03-files-fds-and-proc.md#ghosts-deleted-but-open-files) |
| Illusions | `/proc`, `/sys` pseudo-filesystems | `ls -l /proc/cpuinfo` (size 0) | [03](03-files-fds-and-proc.md#illusions-proc-and-sys) |
| Black holes | `/dev/null`, `/dev/zero`, `/dev/full` | `ls -l /dev/null` → `c 1,3` | [03](03-files-fds-and-proc.md#black-holes-devnull-and-friends) |
| Sleepers | `D` state (uninterruptible) | `ps -eo pid,stat,wchan:32,cmd \| awk '$2~/D/'` | [04](04-tracing-and-debugging.md#sleepers-d-state) |
| Spies | `strace`, `perf`, eBPF | `strace -fp PID -tt -T` | [04](04-tracing-and-debugging.md#spies-strace-perf-ebpf) |
| Prisoners | cgroups v2 | `systemd-cgtop`, `systemd-cgls` | [05](05-cgroups-and-namespaces.md#prisoners-cgroups) |
| Parallel universes | Namespaces | `lsns`, `nsenter -t PID -n ip a` | [05](05-cgroups-and-namespaces.md#parallel-universes-namespaces) |
| Daemons | systemd units | `systemctl list-units --type=service --state=failed` | [06](06-systemd-logs-and-time.md#daemons-systemd) |
| Detectives | journald | `journalctl -u svc -b -p err` | [06](06-systemd-logs-and-time.md#detectives-journald) |
| Time travelers | Epoch, clocks, NTP | `date -u -d @0`, `chronyc tracking` | [06](06-systemd-logs-and-time.md#time-travelers) |
| Bouncers | netfilter / nftables / conntrack | `nft list ruleset`, `conntrack -S` | [07](07-networking-and-firewall.md) |

## Files

| # | File | Covers |
|---|---|---|
| 01 | [Process lifecycle](01-process-lifecycle.md) | fork/clone/exec, states, zombies, orphans, PID 1, signals, fork bombs |
| 02 | [Memory and OOM](02-memory-and-oom.md) | VSZ/RSS/PSS, page cache, overcommit, OOM killer, cgroup OOM, K8s OOMKilled |
| 03 | [Files, fds and /proc](03-files-fds-and-proc.md) | VFS, inodes, deleted-open files, fd limits, procfs, /dev devices |
| 04 | [Tracing and debugging](04-tracing-and-debugging.md) | D state, load average, strace vs perf vs eBPF, hung tasks |
| 05 | [cgroups and namespaces](05-cgroups-and-namespaces.md) | cgroup v2, CPU throttling, namespaces, how containers are built, OpenShift link |
| 06 | [systemd, logs and time](06-systemd-logs-and-time.md) | units, ordering, journald, epoch, chrony, Y2038 |
| 07 | [Networking and firewall](07-networking-and-firewall.md) | netfilter hooks, nftables/firewalld, conntrack, TCP states, queues |
| 08 | [Production scenarios (RCA format)](08-production-scenarios.md) | 12 real-world incidents to tell as interview stories |
| 09 | [Rapid-fire Q&A](09-rapid-fire-qa.md) | 60 short questions for last-day revision |

## How to use this

1. **Read one file per day**, then do its **Lab** section on a throwaway RHEL 8/9 (or Rocky / AlmaLinux) VM. Never run them on a shared or production machine.
2. For every scenario in file 08, practise saying it out loud in **2 minutes**: symptom → triage → root cause → fix → prevention.
3. Night before an interview: file 09 only.
4. Tie every answer back to **containers/OpenShift** where you can. That's the bridge from "senior Linux admin" to "platform engineer".

> Labs assume RHEL 8/9 (`dnf install -y strace lsof psmisc sysstat bcc-tools perf conntrack-tools stress-ng` — `stress-ng` is in EPEL).
