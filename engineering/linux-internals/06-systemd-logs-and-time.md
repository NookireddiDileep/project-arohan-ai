# 06 – systemd, Logs and Time ("Daemons", "Detectives", "Time travelers")

## Boot path (one-breath version for interviews)

Firmware (UEFI/BIOS) → GRUB2 (`/boot/grub2/grub.cfg`, BLS entries in `/boot/loader/entries`) → kernel + **initramfs** (dracut) → systemd inside initramfs finds and mounts root (LVM, multipath, LUKS, iSCSI) → `switch_root` → real systemd (PID 1) → `default.target` (`multi-user.target` / `graphical.target`).

Rescue knobs: `rd.break` (stop in initramfs), `systemd.unit=emergency.target` / `rescue.target`, `rd.debug`, `init=/bin/bash`, `enforcing=0`. For deep practice, break the boot of a throwaway VM on purpose (bad `/etc/fstab` entry, missing initramfs, lost root password) and recover it.

## Daemons: systemd

### Unit essentials
```ini
[Unit]
Description=My app
Wants=network-online.target
After=network-online.target remote-fs.target

[Service]
Type=notify            # simple | exec | forking | oneshot | notify
ExecStart=/opt/app/bin/app
Restart=on-failure
RestartSec=5
User=app
LimitNOFILE=65536
MemoryMax=2G
TasksMax=512
OOMScoreAdjust=-500
Environment=JAVA_OPTS=-Xmx1g

[Install]
WantedBy=multi-user.target
```

**Senior-level distinctions:**
- **`Requires=`/`Wants=` = dependency** (start it too). **`After=`/`Before=` = ordering** only. You usually need both. `Wants=` without `After=` starts them in parallel. Classic bug: app starts before the network/NFS is ready.
- `network.target` ≠ network is up. Use `network-online.target` (+ `NetworkManager-wait-online`).
- `Type=simple`: systemd considers it started the instant it forks. `Type=notify`: waits for `sd_notify(READY=1)`, so dependants start only when it's really ready. `Type=forking`: legacy daemons, needs `PIDFile=`.
- **Start-limit**: crash-looping more than `StartLimitBurst` (5) in `StartLimitIntervalSec` (10s) → unit enters failed state with `start-limit-hit`. `systemctl reset-failed`.
- Overrides: `systemctl edit unit` → `/etc/systemd/system/unit.d/override.conf`. Never edit `/usr/lib/systemd/system`. `systemctl cat unit` shows the merged result.
- Environment differs from your shell: no `~/.bash_profile`, minimal PATH, different SELinux context. That's why "works when I run it manually, fails as a service".

```bash
systemctl --failed
systemctl status app -l --no-pager
systemctl show app -p MainPID,ExecMainStatus,Result,NRestarts,MemoryCurrent,TasksCurrent
systemctl list-dependencies app ; systemctl list-dependencies --reverse app
systemd-analyze blame ; systemd-analyze critical-chain app.service
systemd-analyze verify /etc/systemd/system/app.service
```

## Detectives: journald

- Binary, structured, indexed log store. Each entry has fields: `_PID`, `_UID`, `_SYSTEMD_UNIT`, `_COMM`, `PRIORITY`, `_BOOT_ID`, `_HOSTNAME`.
- **Persistence:** by default on RHEL logs live in `/run/log/journal` (volatile) **unless `/var/log/journal` exists** (`Storage=auto`). No persistent journal = no logs from before the crash/reboot. First thing to check in a post-reboot RCA. Fix: `mkdir -p /var/log/journal; systemd-tmpfiles --create --prefix /var/log/journal; systemctl restart systemd-journald` or `Storage=persistent`.
- **Rate limiting:** `Suppressed N messages from app.service` → `RateLimitIntervalSec`/`RateLimitBurst` in `journald.conf`. Logs did happen, they were dropped.

```bash
journalctl -u app -b -p warning --no-pager       # this boot, warning and above
journalctl -b -1 -p err                          # previous boot (needs persistent journal)
journalctl --list-boots
journalctl -k -b -1 | tail -50                   # kernel log before the last reboot (panic/OOM/hung task)
journalctl --since "2026-11-16 02:00" --until "02:30"
journalctl _PID=1234 ; journalctl _COMM=sshd ; journalctl -t CROND
journalctl -u app -o json-pretty -n 1             # all fields
journalctl --disk-usage ; journalctl --vacuum-size=1G
journalctl -f -u kubelet -u crio                 # follow multiple units
```

**RCA habit for "server rebooted unexpectedly":** `last -x | head` (shutdown/reboot records) → `journalctl -b -1 -n 200` (last messages: clean shutdown or abrupt cut?) → `journalctl -k -b -1` (panic, MCE, OOM, hung task) → hardware logs (iLO/iDRAC IML, `ipmitool sel list`) → kdump in `/var/crash` (`crash` utility).

## Time travelers

### Epoch and clocks
- Unix time = seconds since **1970-01-01 00:00:00 UTC**, ignoring leap seconds.
- `date -d @0` prints in your **local timezone** (in IST: `Thu Jan 1 05:30:00 IST 1970`). Use `date -u -d @0` for UTC.
- **Y2038:** a signed 32-bit `time_t` overflows at **2038-01-19 03:14:07 UTC**. 64-bit Linux uses 64-bit `time_t`. Risk remains in 32-bit embedded systems, old file formats, and databases storing 32-bit timestamps.
- Kernel clocks: `CLOCK_REALTIME` (wall clock, can jump), `CLOCK_MONOTONIC` (never goes back, use for timeouts/durations), `CLOCK_BOOTTIME` (includes suspend). An app measuring timeouts with REALTIME breaks when NTP steps the clock.
- RTC (hardware clock) vs system clock: `hwclock --show`, `timedatectl` (RTC in local TZ = bad on servers).

### NTP with chrony
```bash
timedatectl
chronyc tracking            # System time offset, Leap status, Stratum
chronyc sources -v          # ^* = selected source, ^? = unreachable
chronyc makestep            # step now instead of slewing
```
- **Slew** = gradually speed up/slow down the clock (safe). **Step** = jump (can confuse apps). chrony's `makestep 1.0 3` allows steps only in the first 3 updates after boot.
- Why time matters in production: **Kerberos/AD** fails at >5 min skew, **TLS** certificate "not yet valid", **etcd/OpenShift** cluster health and cert rotation, distributed DB consistency, log correlation during an incident, TOTP/MFA.
- Blocked UDP 123 by a firewall is the usual reason chrony shows `^?`.

## Lab

```bash
# 1. Crash loop → start-limit-hit
sudo tee /etc/systemd/system/demo.service >/dev/null <<'EOF'
[Unit]
Description=demo
[Service]
Type=simple
ExecStart=/bin/bash -c 'echo started; sleep 2; exit 1'
Restart=always
RestartSec=1
EOF
sudo systemctl daemon-reload; sudo systemctl start demo; sleep 15
systemctl status demo --no-pager | head -5        # start-limit-hit
journalctl -u demo --no-pager | tail
sudo systemctl stop demo; sudo rm /etc/systemd/system/demo.service; sudo systemctl daemon-reload; sudo systemctl reset-failed

# 2. Is the journal persistent?
ls -d /var/log/journal && journalctl --list-boots | tail -3

# 3. Time
date -d @0; date -u -d @0; date -u -d @2147483647
```

## Interview questions

1. **`Wants` vs `Requires` vs `After`?** Dependency strength vs ordering. Give the network-online example.
2. **Service works when run manually, fails under systemd. Causes?** Environment/PATH, user, working dir, SELinux context (`unconfined_t` vs `*_t`), limits, ordering, `Type` mismatch.
3. **Server rebooted at 3 AM. How do you find out why?** The RCA habit above, and note that it needs a persistent journal.
4. **Why does clock skew break a Kubernetes cluster?** etcd leases/raft timing, cert validity, token expiry, log correlation.
5. **What's Y2038?** 32-bit signed time_t overflow. Where it still bites.
