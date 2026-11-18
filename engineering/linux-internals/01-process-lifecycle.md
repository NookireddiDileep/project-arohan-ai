# 01 – Process Lifecycle: Clones, Zombies, Orphans, Bombs

## Process vs thread (the foundation)

- In the kernel, both are **tasks** (`struct task_struct`). There's no separate "thread" object.
- A **thread** is a task created with `clone()` flags that share resources with its creator: `CLONE_VM` (address space), `CLONE_FILES` (fd table), `CLONE_SIGHAND`, `CLONE_THREAD` (same thread group).
- **PID** you see in `ps` = **TGID** (thread group ID). Each thread has its own **TID**. `ps -eLf` / `ps -T -p PID` / `ls /proc/PID/task/` show threads.
- `top -H` shows per-thread CPU. Classic Java triage: find the hot TID in `top -H -p PID`, convert to hex (`printf '%x\n' TID`), match `nid=0x...` in `jstack` output.

**Interview line:** "Linux doesn't distinguish processes and threads at the scheduler level. Both are tasks. The difference is which resources are shared via clone flags."

## fork, clone, exec

| Call | What it does |
|---|---|
| `fork()` | Creates a child that's a copy of the parent. glibc implements it as `clone(SIGCHLD)`. Memory is **copy-on-write**: pages are shared read-only until either side writes. |
| `vfork()` | Child borrows the parent's memory, parent is suspended until child calls `exec`/`_exit`. Legacy optimisation. |
| `clone()` | The real syscall. Flags decide what is shared (threads) and which **namespaces** are new (`CLONE_NEWPID`, `CLONE_NEWNET`… → containers). |
| `execve()` | Replaces the program image of the **current** process. PID stays the same. |
| `posix_spawn()` | fork+exec in one API (uses `clone(CLONE_VM\|CLONE_VFORK)` internally). Efficient for big parents like JVMs. |

**What `execve()` keeps vs resets** (senior-level detail):
- Keeps: PID, PPID, open fds (unless `O_CLOEXEC`/`FD_CLOEXEC`), cwd, umask, rlimits, cgroup, namespaces, nice value, ignored signals stay ignored.
- Resets: memory mappings, signal handlers (caught → default), pending alt stacks, threads (all other threads die).
- Fd leak bug: a daemon forks a child that inherits a listening socket because it wasn't `CLOEXEC` → port stays bound after the daemon restarts.

### What happens when you type `ls` and press Enter

1. bash reads the line (readline), parses, expands globs/variables, checks aliases → functions → **builtins** (`cd`, `echo`, `export` never fork) → `$PATH` lookup (hashed: `hash -l`).
2. bash calls `clone()` (fork). Child: puts itself in a new process group (job control), sets up redirections with `dup2()`, resets signal handlers.
3. Child calls `execve("/usr/bin/ls", argv, envp)`.
4. Kernel: checks permissions/`noexec` mount, reads the ELF header, finds the interpreter (`/lib64/ld-linux-x86-64.so.2`), maps segments with `mmap`, builds the stack (argv, envp, auxv), jumps to the dynamic loader → loads `libc`, `libselinux`… → `_start` → `__libc_start_main` → `main()`.
5. Parent bash waits with `wait4()`. Child exits → kernel sends `SIGCHLD` → bash reaps it, sets `$?`.

```bash
# See it yourself
strace -f -e trace=process,execve bash -c 'ls /tmp; true'
# Note: with 'bash -c ls' alone, bash skips the fork and just execs (last-command optimisation).
```

## Process states

| `ps` STAT | Kernel state | Meaning |
|---|---|---|
| `R` | TASK_RUNNING | Running or on the run queue |
| `S` | TASK_INTERRUPTIBLE | Sleeping, wakes on event **or signal** (most processes) |
| `D` | TASK_UNINTERRUPTIBLE | Sleeping in kernel, **signals not delivered** (usually I/O) – see [04](04-tracing-and-debugging.md#sleepers-d-state) |
| `T` / `t` | Stopped / traced | `SIGSTOP`/`Ctrl+Z` / stopped under ptrace (gdb, strace) |
| `Z` | EXIT_ZOMBIE | Exited, not reaped |
| `X` | EXIT_DEAD | Being removed (rarely seen) |
| `I` | Idle kernel thread | Since 4.14, so idle kthreads don't inflate load |

Modifiers: `s` session leader, `l` multi-threaded, `+` foreground process group, `<` high priority, `N` low priority (niced), `L` pages locked.

## Zombies

**Mechanism:** On `exit()`, the kernel releases memory, fds, and most resources, but keeps the `task_struct` with the exit code and rusage so the parent can collect it via `wait()`/`waitpid()`/`waitid()`. It sends `SIGCHLD` to the parent. Until the parent waits, the child is a zombie.

**Cost:** almost no memory, but it **holds a PID**. Thousands of zombies → `pid_max` or cgroup `pids.max` exhausted → `fork: Resource temporarily unavailable` (EAGAIN). That's the real outage.

**You cannot kill a zombie**, it's already dead. `kill -9` does nothing.

**Triage:**
```bash
ps -eo pid,ppid,stat,etime,cmd | awk 'NR==1 || $3 ~ /^Z/'
ps -eo ppid,stat | awk '$2 ~ /^Z/ {print $1}' | sort | uniq -c | sort -rn   # which parent owns most zombies
grep -E 'SigCgt|SigIgn' /proc/<PPID>/status   # does parent catch SIGCHLD? (bit 17 = SIGCHLD)
cat /proc/sys/kernel/pid_max; ls /proc | grep -c '^[0-9]'
```

**Fix (in order):**
1. `kill -s SIGCHLD <PPID>`: nudges a parent whose handler missed a signal (signals coalesce, so a buggy handler that reaps only one child per SIGCHLD leaks).
2. Restart/kill the **parent**. Zombies are reparented to PID 1 (or a subreaper), which reaps them immediately.
3. Root-cause in code: a loop of `waitpid(-1, &st, WNOHANG)` in the SIGCHLD handler, or set `SIGCHLD` to `SIG_IGN` / `SA_NOCLDWAIT` so the kernel auto-reaps.

**Containers:** if your app is PID 1 in the container and it never calls `wait()`, every grandchild it orphans becomes a zombie it never reaps. Fix: `tini` / `dumb-init`, `podman run --init`, or `shareProcessNamespace: true` in K8s (pause container becomes PID 1 and reaps).

## Orphans and subreapers

- Parent dies before child → child is **reparented**. The kernel walks up the ancestry looking for a **subreaper** (`prctl(PR_SET_CHILD_SUBREAPER)`). If none, it goes to **PID 1 of that PID namespace**.
- Subreapers in real life: `systemd --user`, `containerd-shim`, `conmon` (CRI-O/Podman), `tini`.
- That's why on a desktop or container host an orphan's PPID isn't always 1.
- **Double-fork daemonisation** (classic SysV daemons): fork → parent exits → `setsid()` → fork again → first child exits. The daemon is orphaned on purpose, adopted by init, and can never reacquire a controlling terminal. With systemd, `Type=simple`/`notify` makes this unnecessary.

```bash
bash -c 'sleep 600 & echo child=$!' ; sleep 1
ps -o pid,ppid,cmd -p $(pgrep -n sleep)      # PPID is 1 or your systemd --user
```

## PID 0, PID 1, PID 2

- **PID 0** = idle task ("swapper"), one per CPU. Created at boot, never visible in `ps` as a row, but is the PPID of 1 and 2.
- `start_kernel()` → `rest_init()` spawns **PID 1** (`kernel_init` → execs `/sbin/init` = systemd) and **PID 2** (`kthreadd`).
- **All kernel threads** (`[kworker/…]`, `[ksoftirqd/N]`, `[kswapd0]`, `[jbd2/…]`) are children of kthreadd (PPID 2), **not** PID 1. So "everything goes back to PID 1" is wrong for kernel threads.
- PID 1 is special:
  - The kernel won't deliver a signal to init unless init installed a handler for it. `kill -9 1` from inside does nothing. (In a container, the host *can* SIGKILL the container's PID 1.)
  - If PID 1 exits → `Kernel panic - not syncing: Attempted to kill init!`. In a PID namespace, PID 1 exiting kills every process in that namespace (the container stops).
  - PID 1 must reap orphans.

```bash
ps -o pid,ppid,cmd -p 1,2
ps -eo pid,ppid,cmd | awk '$2==2' | head     # kernel threads
```

## Signals: what senior candidates know

- `SIGKILL (9)` and `SIGSTOP (19)` can't be caught, blocked or ignored.
- Signals are delivered when the task returns to user space or is woken from an **interruptible** sleep. That's why `kill -9` doesn't work on `D` state: the task never returns to the delivery point until the I/O completes. (`TASK_KILLABLE` is a variant that does allow fatal signals, used by NFS and some newer code.)
- Decode masks: `grep -E '^Sig(Pnd|Blk|Ign|Cgt)|ShdPnd' /proc/PID/status`. Each is a hex bitmask, bit N-1 = signal N.
- **Why `kill -9` "doesn't work":** (1) zombie, already dead; (2) D state; (3) it's PID 1; (4) process was respawned by systemd (`Restart=always`) and you're seeing a new PID; (5) wrong PID namespace.
- **K8s/OpenShift:** on pod delete, kubelet sends `SIGTERM` to PID 1 of each container, waits `terminationGracePeriodSeconds` (default 30), then `SIGKILL`. Shell-form `CMD java …` makes `/bin/sh` PID 1, and sh doesn't forward SIGTERM → app gets killed hard after 30s. Use exec form or `exec java …`.

## Fork bombs and PID exhaustion

`:(){ :|:& };:` defines a function `:` that pipes itself into itself in the background → exponential process growth until no PIDs/memory left.

**Defences, weakest → strongest:**

| Layer | Control | Note |
|---|---|---|
| Per user | `ulimit -u` (RLIMIT_NPROC), `/etc/security/limits.conf` `nproc` | Counted per **real UID** across the system. Applied by `pam_limits` → **only login sessions**, not systemd services. Root (CAP_SYS_RESOURCE/ADMIN) bypasses. |
| System | `kernel.pid_max`, `kernel.threads-max` | Global ceiling; 32768 on old kernels, 4194304 on modern 64-bit systemd systems |
| Per service / user slice | systemd `TasksMax=` (default a % of pid_max), logind `UserTasksMax` | Backed by the cgroup `pids` controller |
| cgroup | `pids.max` in the cgroup | Hard limit, the real isolation |
| Kubernetes | kubelet `podPidsLimit`; OpenShift sets a default (commonly 4096) via `KubeletConfig`/CRI-O | One pod can't exhaust the node's PIDs |

**Recovering a box during a fork bomb** (you can't fork a new process, so `ps`/`pkill` fail):
- Use **builtins** in an already-open root shell: `kill`, `echo`, `exec`.
- Freeze then kill the whole cgroup (cgroup v2, kernel ≥ 5.14 / RHEL 9): `echo 1 > /sys/fs/cgroup/user.slice/user-1001.slice/cgroup.freeze` then `echo 1 > …/cgroup.kill`.
- As the offending user: `kill -9 -1` kills everything that user can signal (including your shell, so never do it as root).

## Lab

```bash
# 1. Zombie
python3 -c 'import os,time
pid=os.fork()
if pid==0: os._exit(0)
print("child",pid); time.sleep(300)' &
sleep 1; ps -eo pid,ppid,stat,cmd | awk '$3~/^Z/'
kill %1            # kill the parent → zombie disappears (reaped by init)

# 2. Orphan
bash -c 'sleep 600 & exit'; ps -o pid,ppid,cmd -p $(pgrep -n sleep); pkill -n sleep

# 3. Contained fork bomb (safe: limited to 50 tasks in a transient scope)
sudo systemd-run --scope -p TasksMax=50 bash -c ':(){ :|:& };:' &
sleep 3; systemd-cgls | grep -A3 run-   # see the scope
sudo systemctl stop 'run-*.scope'

# 4. fork/exec trace
strace -f -e trace=clone,clone3,execve,wait4 bash -c 'ls >/dev/null; echo done'
```

## Interview questions

1. **Difference between fork and exec? Why two calls instead of one?** Splitting them lets the child set up its environment (redirections, setuid, namespaces, cgroups, closing fds) between fork and exec. That's how shells implement `>` and `|`, and how container runtimes set up isolation before exec'ing the entrypoint.
2. **Is fork expensive for a 30 GB JVM?** Copying page tables is O(mapped memory) even with COW, and can take ms + memory. That's why `posix_spawn`/`vfork` exist. Also overcommit: with `vm.overcommit_memory=2`, forking a big process can fail with ENOMEM.
3. **System has 10,000 zombies. Impact and fix?** PID exhaustion, not memory. Find the parent, signal or restart it, fix the reaping bug.
4. **What happens to children when you kill a parent with SIGKILL?** Nothing directly. They're orphaned and reparented. (Unless they set `PR_SET_PDEATHSIG`, or they're in the same systemd service cgroup and systemd stops the unit, `KillMode=control-group`.)
5. **Why does your container leave zombies but the VM doesn't?** On the VM, systemd as PID 1 reaps orphans. In the container your app is PID 1 and doesn't.
6. **`kill -9` didn't kill a process. Why?** List the 5 reasons above.
