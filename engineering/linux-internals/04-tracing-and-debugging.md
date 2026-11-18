# 04 – Tracing and Debugging ("Sleepers" and "Spies")

## Sleepers: D state

**What it is:** `TASK_UNINTERRUPTIBLE`: the task is sleeping inside the kernel waiting for something where being interrupted halfway would leave kernel state inconsistent. Signals (including SIGKILL) are queued but not acted on until it wakes.

**Common causes:**
- Block I/O to a slow/dead device: SAN path failure, dying disk, `multipath` with `queue_if_no_path` (I/O queues forever instead of erroring).
- **NFS hard mount** to an unreachable server (default `hard`: retries forever).
- Page fault that needs to read from a file on a hung filesystem.
- Kernel lock/mutex held by a buggy driver; `fsfreeze`/snapshot in progress (e.g. backup agent freezing XFS).

**Why it matters:** D-state tasks **count in Linux load average** → "load 120, CPU 95% idle". And they can't be killed, so the only real fix is to restore the resource (or reboot).

**Triage:**
```bash
ps -eo pid,stat,wchan:32,etime,cmd | awk 'NR==1 || $2 ~ /D/'
cat /proc/<PID>/stack                # kernel stack: nfs_*, blk_mq_*, xfs_*, rpc_wait_bit_killable …
cat /proc/<PID>/wchan; echo
echo w > /proc/sysrq-trigger; dmesg -T | tail -100      # dump all blocked tasks with stacks
journalctl -k | grep -i 'blocked for more than'        # hung_task detector (default 120s)
iostat -xz 2                         # %util 100, await huge, or r/s w/s = 0 on a device
multipath -ll                        # failed / faulty paths
mount | grep nfs; nfsstat -c; rpcinfo -p <server>
```

**Fix:**
1. Restore the backend: fix the SAN path/zoning, restart the NFS server, replace the disk.
2. NFS: `umount -f` (force) or `umount -l`; future mounts consider `soft,timeo=,retrans=` for non-critical data (risk: silent data corruption on write timeouts), or keep `hard` and monitor.
3. Multipath: `dmsetup message <map> 0 fail_if_no_path` to make queued I/O fail instead of hanging forever.
4. Last resort: reboot (often needs `echo b > /proc/sysrq-trigger` because a clean shutdown hangs on unmount).

## Load average: what it really is

- Exponentially-damped moving average over 1/5/15 min of **tasks in R (running/runnable) + D (uninterruptible)**. The D part is Linux-specific; other Unix systems count only runnable tasks.
- Compare to **CPU count** (`nproc`). Load 16 on 16 cores = saturated; on 64 cores = fine.
- High load + high `%wa` / D tasks → I/O. High load + high `%us`/`%sy` + `vmstat r` > cores → CPU saturation.
- Better modern signal: **PSI** `/proc/pressure/{cpu,io,memory}`.

```bash
uptime; nproc; vmstat 1 5        # r = runnable, b = blocked (D), cs = context switches
mpstat -P ALL 1 3                # per-CPU, look for one CPU at 100% (single-threaded / IRQ)
pidstat -u -d 1 5                # per process CPU and I/O
cat /proc/pressure/io
```
`%st` (steal) in a VM = hypervisor gave your vCPU's time to someone else (VMware "CPU ready"). That's an infra problem, not the guest.

## Spies: strace, perf, eBPF

### strace
- Uses **ptrace**: the tracee stops on **every syscall entry and exit**, and the tracer reads its registers. That's 2 context switches per syscall → **10–100× slowdown** for syscall-heavy apps. Be careful attaching to a busy prod DB.
- Also: only one tracer per process (`strace` fails if gdb is attached), and it needs `CAP_SYS_PTRACE` / `kernel.yama.ptrace_scope`.

```bash
strace -fp PID -tt -T -e trace=network,file -o /tmp/s.out    # -T = time in syscall
strace -c -fp PID            # summary: which syscalls, how many, errors (Ctrl+C after 10s)
strace -f -e trace=openat -e status=failed cmd   # what files did it fail to open? (newer strace)
strace -yy -p PID            # show fd → path/socket
```
What to look for: `ENOENT` on config files, `EACCES` (permissions/SELinux), `connect()` hanging (`-T` shows seconds), `futex` wait (lock contention, needs a stack/profile not strace), `EAGAIN` loops.

### perf
```bash
perf top -p PID                          # live hottest functions
perf record -F 99 -g -p PID -- sleep 30; perf report   # CPU profile with stacks → flame graph
perf trace -p PID                        # strace-like, far lower overhead
perf stat -p PID -- sleep 10             # cycles, instructions, cache misses, context switches
```

### eBPF (bcc-tools / bpftrace)
Safe, verified programs run in kernel, aggregate in kernel → production-friendly. RHEL: `dnf install bcc-tools` → `/usr/share/bcc/tools/`.

| Tool | Answers |
|---|---|
| `execsnoop` | What short-lived processes are being spawned? (catches cron storms, crash loops invisible to `top`) |
| `opensnoop` | Which files are opened, and which fail? |
| `biolatency`, `biosnoop` | Disk I/O latency histogram / per I/O |
| `tcpconnect`, `tcpaccept`, `tcpretrans` | Connections and retransmits |
| `offcputime` | Where are threads **blocked** (the complement to CPU profiling) |
| `runqlat` | How long do tasks wait for a CPU? |
| `oomkill` | Live OOM-kill events with details |

```bash
bpftrace -e 'tracepoint:syscalls:sys_enter_openat { printf("%s %s\n", comm, str(args->filename)); }'
```

### Other tools
- `ltrace`: library calls. `gdb -p PID` / `gcore PID` / `pstack PID`: user stacks. `jstack` / `py-spy dump`: language runtime stacks.
- `/proc/PID/stack` (kernel stack) + user stack = the full picture of where a process is stuck.

## Debugging decision tree (say this in interviews)

```
Process slow / hung
├─ State R, high CPU   → perf top / perf record (where is CPU spent?)
├─ State S, low CPU    → strace -T / offcputime (what is it waiting on? network? lock?)
├─ State D             → /proc/PID/stack, iostat, multipath, NFS (storage path)
├─ State Z             → parent isn't reaping
└─ State T             → someone sent SIGSTOP or a debugger is attached
```

## Lab

```bash
# D state on demand: freeze a filesystem
sudo mkdir -p /mnt/frz && sudo truncate -s 200M /tmp/frz.img && sudo mkfs.xfs -q /tmp/frz.img
sudo mount -o loop /tmp/frz.img /mnt/frz
sudo fsfreeze -f /mnt/frz
sudo bash -c 'echo hi > /mnt/frz/x' &           # this writer goes D
sleep 2; ps -eo pid,stat,wchan:32,cmd | awk '$2~/D/'
sudo cat /proc/$(pgrep -n -f 'echo hi')/stack; uptime
sudo fsfreeze -u /mnt/frz; sudo umount /mnt/frz

# strace overhead
time dd if=/dev/zero of=/dev/null bs=1 count=500000
time strace -o /dev/null dd if=/dev/zero of=/dev/null bs=1 count=500000

# eBPF
sudo /usr/share/bcc/tools/execsnoop    # then run commands in another terminal
```

## Interview questions

1. **Load average is 80 on a 16-core box but CPU is 90% idle. What's going on?** D-state tasks waiting on I/O count in load. Show the commands.
2. **Why can't SIGKILL kill a D-state process?** Signal delivery happens on the way back to user space / on interruptible wake-up. The task is parked uninterruptibly in kernel code.
3. **Would you run strace on a production database?** Briefly and scoped (`-e`), knowing the overhead; prefer `perf trace` or eBPF tools.
4. **How do you find what a hung process is waiting for?** State → `wchan`/`/proc/PID/stack` → strace -p (if S) → user stack (gdb/jstack).
5. **What's steal time?** Hypervisor contention. Escalate to the virtualization team, the guest can't fix it.
