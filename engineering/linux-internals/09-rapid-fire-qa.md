# 09 – Rapid-Fire Q&A (night-before revision)

Cover the answer, say it aloud, check. Target: under 20 seconds each.

## Processes
1. **Process vs thread in the kernel?** Both are tasks (`task_struct`); threads share mm/files/signals via clone flags.
2. **What does fork return?** 0 in child, child PID in parent, −1 on error.
3. **What does exec keep?** PID, fds without CLOEXEC, cwd, rlimits, cgroup, namespaces.
4. **Copy-on-write?** Pages shared read-only after fork; copied on first write.
5. **Zombie?** Exited, exit status not yet collected by the parent with wait().
6. **How to clear zombies?** Make the parent reap (SIGCHLD / fix code) or kill the parent.
7. **Orphan's new parent?** Nearest subreaper, else PID 1 of the PID namespace.
8. **PPID of kernel threads?** 2 (kthreadd).
9. **PID 0?** The per-CPU idle (swapper) task.
10. **What if PID 1 dies?** Kernel panic (host) / every process in the namespace is killed (container).
11. **Uncatchable signals?** SIGKILL, SIGSTOP.
12. **Exit code 137?** 128 + 9 → killed by SIGKILL (often OOM).
13. **Exit code 143?** 128 + 15 → SIGTERM.
14. **Why shell-form CMD breaks graceful shutdown?** `sh` is PID 1 and doesn't forward SIGTERM.
15. **Fork bomb defence in K8s?** `podPidsLimit` (cgroup pids.max).

## Memory
16. **VSZ vs RSS vs PSS?** Virtual / resident / resident with shared pages divided.
17. **Which `free` column matters?** `available`.
18. **What triggers OOM killer?** Allocation fails after reclaim.
19. **How does it pick?** Memory footprint proportion + oom_score_adj.
20. **Make a process unkillable by OOM?** `oom_score_adj = -1000` / `OOMScoreAdjust=-1000`.
21. **Pod OOMKilled with free node memory?** Hit its own cgroup memory.max.
22. **Eviction vs OOM kill?** Kubelet node-pressure policy vs kernel cgroup/global kill.
23. **QoS oom_score_adj?** Guaranteed −997, BestEffort 1000, Burstable 2–999.
24. **overcommit_memory=2?** Strict accounting; malloc fails instead of OOM kill.
25. **Why disable THP for DBs?** Compaction/khugepaged latency stalls.
26. **Minor vs major page fault?** In RAM, just map / must read from disk.

## Files
27. **Where is a filename stored?** In the directory entry, not the inode.
28. **When is a deleted file's space freed?** Link count 0 and no open fds.
29. **Find deleted-open files?** `lsof +L1`.
30. **Free that space without restart?** `: > /proc/PID/fd/N`.
31. **EMFILE vs ENFILE?** Per-process vs system-wide fd limit.
32. **Why limits.conf doesn't apply to services?** pam_limits only runs for login sessions; use LimitNOFILE.
33. **Why /proc files show size 0?** Generated on read.
34. **/dev/null major,minor?** 1,3.
35. **Test app behaviour on disk full?** Write to `/dev/full`.
36. **df full, du low, no deleted files?** Files under a mount point, reserved blocks, inodes (`df -i`).

## Debugging
37. **D state?** Uninterruptible sleep in kernel, usually I/O.
38. **Why can't kill -9 kill D?** Signal acted on only when the task wakes/returns to user space.
39. **Load average counts?** Runnable + uninterruptible tasks.
40. **Find where a hung process is blocked in kernel?** `/proc/PID/stack`, `wchan`, `echo w > /proc/sysrq-trigger`.
41. **strace overhead source?** ptrace stops on every syscall entry/exit.
42. **Low-overhead alternatives?** `perf trace`, eBPF (bcc/bpftrace).
43. **Catch short-lived processes?** `execsnoop`.
44. **%st in top?** Steal time, hypervisor contention.
45. **hung_task message?** "task X blocked for more than 120 seconds".

## cgroups / namespaces
46. **cgroup v2 CPU limit file?** `cpu.max` (quota period).
47. **Throttling evidence?** `cpu.stat` nr_throttled / throttled_usec.
48. **requests.cpu maps to?** `cpu.weight`.
49. **List namespaces?** `lsns`.
50. **Enter a container's network namespace from the node?** `nsenter -t PID -n`.
51. **What holds a pod's network namespace?** The pause/infra container.
52. **8 namespace types?** mnt, uts, ipc, pid, net, user, cgroup, time.
53. **Why does OpenShift run containers as random UIDs?** restricted-v2 SCC, defence in depth with SELinux MCS.

## systemd / logs / time
54. **After vs Wants?** Ordering vs dependency.
55. **Logs from previous boot?** `journalctl -b -1` (needs persistent journal).
56. **Crash loop stops restarting?** start-limit-hit (StartLimitBurst/IntervalSec).
57. **`date -d @0` in IST?** 05:30 on 1 Jan 1970 (use `-u` for UTC midnight).
58. **Y2038 moment?** 2038-01-19 03:14:07 UTC.

## Networking
59. **Timeout vs refused?** Drop (firewall/route) vs no listener/REJECT.
60. **Many CLOSE_WAIT?** App not closing sockets, an app bug.
