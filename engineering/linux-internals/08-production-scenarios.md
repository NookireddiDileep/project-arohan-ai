# 08 – Production Scenarios (RCA format)

Interviewers at senior level ask **"Tell me about a time…"** or **"A server does X, walk me through it."** Use this structure every time, in about 2 minutes:

> **Symptom → Hypotheses → Evidence (commands) → Root cause → Fix → Prevention**

Practise each one out loud. Where you've handled something similar in your own environment, swap in your real story.

---

## S1. Filesystem 100% but `du` shows 40%
- **Symptom:** `/var` 100%, alert firing, app write failures. `du -xsh /var` = 40%.
- **Hypotheses:** deleted-open files, files under a mount point, reserved blocks, inode exhaustion.
- **Evidence:** `lsof +L1 /var` → `java` holds `/var/log/app/app.log.1 (deleted)`, 38 GB.
- **Root cause:** logrotate renamed and deleted the log, but the app kept writing to the old fd (no `copytruncate`, no reopen signal).
- **Fix:** `: > /proc/<PID>/fd/<FD>`. Space freed with no restart.
- **Prevention:** logrotate `postrotate systemctl reload app` (or `copytruncate`), alert on `df` vs `du` drift, log volume sizing.

## S2. Load average 120 on 16 cores, CPU 92% idle
- **Evidence:** `vmstat 1` → `b` column 110; `ps … awk '$2~/D/'` → 110 processes in `D`, `wchan` = `rpc_wait_bit_killable`; `/proc/PID/stack` shows `nfs_*`; `mount` shows NFS `hard`; NFS server unreachable.
- **Root cause:** NFS server failover hung; hard mount → every process touching the share went D. (Block-storage variant: FC path failure with `queue_if_no_path`, `multipath -ll` shows all paths failed.)
- **Fix:** restore NFS server / storage path; processes resume automatically. If unrecoverable, `umount -f -l`, reboot.
- **Prevention:** monitor NFS/multipath path health, don't put NFS in critical login paths (`$HOME`, `$PATH`), `nofail` / automount for non-critical shares.

## S3. Java app dies at night, no error in app log
- **Evidence:** `journalctl -k | grep -i 'killed process'` → `Out of memory: Killed process 4127 (java) anon-rss:7.8G`. Or in a container: `memory.events oom_kill 1`, pod `OOMKilled`, exit 137.
- **Root cause:** batch job + heap growth; heap 6G + metaspace + threads + direct buffers > 8G limit. (Or another process ballooned and java had the highest `oom_score`.)
- **Fix:** right-size `-Xmx` / `MaxRAMPercentage`, raise limit, find the leak (heap dump on OOM: `-XX:+HeapDumpOnOutOfMemoryError`).
- **Prevention:** memory alerts at 85% of limit, `OOMScoreAdjust` for critical daemons, PSI monitoring.

## S4. "fork: Resource temporarily unavailable", can't even SSH
- **Evidence:** from an existing root session: `ps -eo stat | grep -c Z` → 31,000 zombies, all with the same PPID; or `cat /sys/fs/cgroup/user.slice/user-1001.slice/pids.current` at max.
- **Root cause:** a monitoring script spawned children and never `wait()`ed (zombie leak) → PID/TasksMax exhausted. Alternative: runaway thread creation in an app.
- **Fix:** kill the parent → zombies reaped by init. For a runaway cgroup: `cgroup.freeze` + `cgroup.kill`.
- **Prevention:** `TasksMax` per service, alert on process count, fix reaping in code, `podPidsLimit` in K8s.

## S5. "Too many open files" after raising limits.conf
- **Evidence:** `cat /proc/<PID>/limits` → `Max open files 1024 4096` despite `limits.conf` = 65536. `ls /proc/PID/fd | wc -l` = 1024.
- **Root cause:** service started by systemd; `pam_limits` never applies. Possibly also an fd leak (count keeps growing).
- **Fix:** `LimitNOFILE=65536` via `systemctl edit`, restart, verify in `/proc/PID/limits`.
- **Prevention:** limits in unit files/Ansible role, monitor fd usage %, check for leaks (`lsof -p PID | awk '{print $5}' | sort | uniq -c`).

## S6. Service fails after reboot, starts fine manually
- **Evidence:** `journalctl -b -u app` → `cannot connect to db.example: Name or service not known` at boot; works 2 min later.
- **Root cause:** `After=network.target` only. DNS/network wasn't up yet. (Variants: NFS mount not ready → `After=remote-fs.target`/`RequiresMountsFor=`; SELinux label on a new binary path → `restorecon`; env var only in user profile.)
- **Fix:** `Wants=network-online.target` + `After=network-online.target`, `Restart=on-failure`.
- **Prevention:** reboot tests during DR/fire drills, `systemd-analyze verify`.

## S7. Container latency spikes, node CPU idle
- **Evidence:** p99 jumps from 50 ms to 900 ms; node 25% CPU; `cpu.stat nr_throttled` climbing; `container_cpu_cfs_throttled_periods_total` > 30%.
- **Root cause:** CPU limit 1 core, JVM with 16 GC/app threads burns 100 ms quota in a burst, throttled for the rest of each 100 ms period.
- **Fix:** raise the limit or remove it (keep requests), cap threads (`-XX:ActiveProcessorCount=2`).
- **Prevention:** throttling dashboards, limit policy reviewed with app teams.

## S8. Intermittent timeouts at peak, server looks healthy
- **Evidence:** `dmesg` → `nf_conntrack: table full, dropping packet`; `conntrack -S` drop/insert_failed rising. Or `nstat` `ListenOverflows` rising and `ss -lnt` Recv-Q = Send-Q (accept queue full).
- **Root cause:** conntrack table sized for defaults on a busy NAT/K8s node; or app accept loop starved (thread pool exhausted).
- **Fix:** raise `nf_conntrack_max`/hashsize, lower timeouts; raise `somaxconn` + app backlog, fix thread pool.
- **Prevention:** alert on conntrack utilisation and listen overflows.

## S9. Kerberos / AD logins fail across a set of servers
- **Evidence:** `kinit: Clock skew too great`; `chronyc sources` → all `^?`; `chronyc tracking` offset 7 min.
- **Root cause:** firewall change blocked UDP 123 to NTP servers; clocks drifted beyond Kerberos's 5-minute tolerance.
- **Fix:** restore firewall rule, `chronyc makestep`.
- **Prevention:** alert on `chronyc tracking` offset > 1s, include NTP in firewall change checklists.

## S10. `kill -9` doesn't remove the process
- **Evidence:** `ps -o stat` → `Z` (zombie: kill the parent) or `D` (stuck in I/O: fix storage). Or `systemctl status` shows a new PID (systemd restarted it: stop the unit instead).
- **Point to make:** "kill -9 not working" is never a reason to reboot first. Identify the state.

## S11. `umount: target is busy` during a maintenance window
- **Evidence:** `fuser -vm /data` → a backup agent and an admin shell with cwd in `/data`.
- **Fix:** stop the agent cleanly, `cd /`, umount. Lazy umount only if you understand the consequences.
- **Prevention:** pre-checks in the change plan (`fuser`/`lsof` step), stop dependent services in order.

## S12. Unexpected reboot at 03:12
- **Evidence:** `last -x` shows no clean shutdown; `journalctl -b -1 -n 50` ends abruptly; `journalctl -k -b -1` shows `mce: [Hardware Error]` / or nothing; iLO/iDRAC IML shows a correctable → uncorrectable memory error; `/var/crash` vmcore if kdump was configured.
- **Root cause:** DIMM failure → machine check → reset.
- **Fix:** vendor spare replacement (DIMM), move workloads, memory test.
- **Prevention:** kdump enabled and tested, persistent journal, hardware log forwarding, alerts on correctable ECC errors (they precede uncorrectable ones).

---

## Turning your own experience into stories
Pick 3–4 of these that map to real incidents you handled (security-patch reboots, DR drills, backup jobs freezing I/O and causing D state, monitoring or security agents eating memory or file descriptors) and write each one in the format above with **numbers**: how many servers, how long, what impact. Real numbers make stories credible.
