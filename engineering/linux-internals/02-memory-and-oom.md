# 02 – Memory and the OOM Killer ("Killers")

## Virtual memory in 60 seconds

- Every process gets its own **virtual address space**. The MMU translates virtual → physical pages (4 KiB) using **page tables**; the TLB caches translations.
- `malloc()` reserves *virtual* space (`brk`/`mmap`). Physical pages are only allocated on **first touch** (page fault). This is why **VSZ** can be huge and harmless.
- **Minor fault**: page is in RAM (e.g. page cache, COW) and just needs mapping. **Major fault**: must be read from disk (swap or file) → slow. `ps -o min_flt,maj_flt -p PID`, `sar -B`.

## Measuring process memory correctly

| Metric | Meaning | Trap |
|---|---|---|
| VSZ | Total virtual mapping | Meaningless for "how much RAM" |
| RSS | Resident pages mapped by the process | Counts **shared** libs/shm fully in every process → sum of RSS > total RAM |
| PSS | RSS with shared pages divided among sharers | Best for "who uses RAM" across many processes |
| USS | Private pages only | What you'd free by killing it |

```bash
grep -E 'Rss|Pss|Private|Swap' /proc/PID/smaps_rollup
pmap -x PID | tail -1
smem -tk          # PSS/USS per process (EPEL)
```

## "free shows almost no free memory": the most common interview trap

```
              total   used   free  shared  buff/cache  available
Mem:           31Gi   9Gi   0.4Gi   1.2Gi       21Gi       20Gi
```
- Linux uses spare RAM for **page cache**. That's good, and it's reclaimable.
- Look at **`available`** (kernel estimate of memory usable without swapping, from `MemAvailable` in `/proc/meminfo`), not `free`.
- When `available` is low but no process has big RSS, check:
  - **Slab** (`grep -E 'Slab|SReclaimable|SUnreclaim' /proc/meminfo`, `slabtop -o`): dentry/inode cache explosion, kernel leaks.
  - **Shmem / tmpfs** (`df -h -t tmpfs`): files in `/dev/shm`, `/run`, deleted-but-open tmpfs files.
  - **HugePages** reserved (`HugePages_Total` × `Hugepagesize`): reserved and invisible to normal apps.
  - Kernel memory from drivers (e.g. ZFS ARC, GPU drivers).

## Overcommit

| `vm.overcommit_memory` | Behaviour |
|---|---|
| 0 (default) | Heuristic: refuses only obviously impossible allocations |
| 1 | Always allow (Redis, some HPC). OOM killer becomes the safety net |
| 2 | Strict: commit limit = swap + `overcommit_ratio`% of RAM. `malloc` fails with ENOMEM instead of OOM kill |

`grep -E 'CommitLimit|Committed_AS' /proc/meminfo`. With mode 2, `Committed_AS` can't exceed `CommitLimit`.

## The OOM killer (global)

**When it runs:** a page allocation can't be satisfied even after direct reclaim (dropping page cache, swapping, compacting). The kernel must pick a victim or panic (`vm.panic_on_oom`).

**How it picks:** `oom_badness()` ≈ the task's RSS + swap + page-table pages as a proportion of allowed memory, then adjusted by `oom_score_adj` (−1000…+1000). Result exposed in `/proc/PID/oom_score` (0–1000). Biggest score dies. `-1000` = never kill (sshd, critical agents).

```bash
for p in /proc/[0-9]*; do printf "%s %s %s\n" "$(cat $p/oom_score 2>/dev/null)" "${p#/proc/}" "$(cat $p/comm 2>/dev/null)"; done | sort -rn | head
echo -500 > /proc/PID/oom_score_adj       # or OOMScoreAdjust= in the systemd unit
```

**Evidence after the fact:**
```bash
journalctl -k | grep -iE 'out of memory|oom-kill|killed process'
dmesg -T | grep -iE -A20 'invoked oom-killer'
```
Typical line:
```
Out of memory: Killed process 4127 (java) total-vm:12854320kB, anon-rss:7801224kB, file-rss:0kB, shmem-rss:0kB, UID:1001 pgtables:15872kB oom_score_adj:0
```
Read the table above it: it lists every task's RSS at the moment of the kill. That's your RCA evidence.

## cgroup OOM vs global OOM (critical for containers)

- With a **memory limit** (`memory.max` in cgroup v2), the OOM is scoped to that cgroup: `Memory cgroup out of memory: Killed process …`. The node may have 100 GB free.
- `cat /sys/fs/cgroup/<path>/memory.events` → `oom`, `oom_kill` counters. `memory.high` = throttle + reclaim before hitting `memory.max`.
- **Kubernetes/OpenShift:**
  - Container exceeds `limits.memory` → kernel cgroup OOM kill → `Reason: OOMKilled`, `Exit Code: 137` (128 + SIGKILL 9).
  - **Eviction** is different: kubelet sees node `memory.available` below threshold and evicts pods (status `Evicted`), BestEffort first.
  - QoS sets `oom_score_adj`: **Guaranteed −997**, **BestEffort 1000**, **Burstable** 2–999 scaled by request. So under global pressure, BestEffort dies first.
- **JVM in containers:** Java 10+ (and 8u191+) read the cgroup limit. Heap (`-Xmx` or `MaxRAMPercentage`) + metaspace + thread stacks + direct buffers + code cache must fit under the limit, or you get OOMKilled with no Java `OutOfMemoryError` in the logs.

## Swap and reclaim

- `vm.swappiness` (0–200 on newer kernels): bias between reclaiming anon pages (swap) vs file pages (cache). Not "when to start swapping".
- `kswapd` reclaims in the background between watermarks (`/proc/zoneinfo` min/low/high). Below `min` → **direct reclaim** in the allocating process → latency spikes.
- K8s historically requires swap off (now beta support for swap on cgroup v2).
- **PSI** (pressure stall information): `cat /proc/pressure/memory` → `some`/`full` % of time tasks stalled on memory. Better signal than "free memory". Per cgroup: `memory.pressure`.

## HugePages and THP

- **Static HugePages** (2 MiB/1 GiB): preallocated, non-swappable, fewer TLB misses. Oracle DB, DPDK, some HPC. `vm.nr_hugepages`.
- **Transparent HugePages (THP)**: kernel automatically promotes; `khugepaged` compaction can cause latency stalls. DB vendors (Oracle, MongoDB, Redis) recommend `never` or `madvise`: `cat /sys/kernel/mm/transparent_hugepage/enabled`.

## Lab

```bash
# 1. cgroup OOM on demand (safe)
sudo systemd-run --scope -p MemoryMax=100M -p MemorySwapMax=0 \
  python3 -c 'a=bytearray(300*1024*1024); print("survived")'
journalctl -k -n 30 | grep -iE 'memory cgroup|killed process'

# 2. Page cache is reclaimable
free -h; dd if=/dev/zero of=/tmp/big bs=1M count=2000; free -h
sync; echo 1 | sudo tee /proc/sys/vm/drop_caches; free -h; rm /tmp/big

# 3. Protect a process
sleep 1000 & echo -1000 | sudo tee /proc/$!/oom_score_adj; cat /proc/$!/oom_score
```

## Interview questions

1. **App was killed overnight, no errors in app logs. How do you prove it was OOM?** `journalctl -k`/`dmesg` for oom-kill, the per-task table, `memory.events` in its cgroup, `sar -r` history, K8s `kubectl describe pod` → OOMKilled/137.
2. **RSS of all processes adds up to 150% of RAM. Bug?** No, shared pages are counted multiple times. Use PSS.
3. **How does the OOM killer choose?** Memory footprint proportion + `oom_score_adj`. Not CPU, not age (older kernels had heuristics, removed in 2.6.36).
4. **Pod OOMKilled but node has free memory. Why?** The container hit its own cgroup `memory.max`; node free memory is irrelevant.
5. **Difference between eviction and OOM kill?** Eviction is kubelet (user space, graceful-ish, whole pod, based on node signals). OOM kill is the kernel (instant SIGKILL, single process, based on cgroup or global limit).
6. **Would you disable the OOM killer?** No. Without it the box hangs or panics. Instead size limits, set `oom_score_adj` for critical daemons, and use `memory.high` for back-pressure.
