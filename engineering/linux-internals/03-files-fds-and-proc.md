# 03 – Files, File Descriptors, /proc and /dev ("Ghosts, Illusions, Black holes")

## The VFS object model

```
process ── fd table ──> struct file (open file description: offset, flags) ──> dentry ──> inode ──> data blocks
            (per process, ints 0,1,2…)   (shared after fork/dup)                (name)     (metadata)
```
- **inode** = file metadata + block pointers. **No filename** inside the inode.
- **dentry** = name → inode mapping (directory entry), cached in the dentry cache.
- **Link count** (`stat -c %h`) = number of names pointing to the inode.
- **fd** = index into the process fd table → open file description. After `fork()`, parent and child share the same description (and file offset). That's why two processes writing to the same inherited log fd don't overwrite each other.

## Ghosts: deleted-but-open files

`rm` calls `unlink()`, which removes the **name** and decrements the link count. The kernel frees the blocks only when **link count = 0 AND no open references**. A running process holding the file keeps the space allocated → `df` shows full, `du` can't find it.

**Triage:**
```bash
df -h /var ; du -xsh /var          # mismatch = suspect deleted-open files
lsof +L1                           # open files with link count < 1
lsof -nP +L1 /var | sort -k7 -rn | head
ls -l /proc/*/fd 2>/dev/null | grep '(deleted)'
```

**Fix without restarting the app:**
```bash
# find PID and FD number from lsof (FD column e.g. 4w → fd 4)
: > /proc/<PID>/fd/<FD>            # truncate to 0 bytes, space released immediately
cp /proc/<PID>/fd/<FD> /tmp/recovered.log   # or recover the content first
```
Then fix the root cause: logrotate without `copytruncate` or a `postrotate` signal (`kill -HUP` / `systemctl reload`) so the app reopens its log.

**Other df vs du mismatch causes** (say these to sound senior):
1. Files hidden **under a mount point** (written before the filesystem was mounted). Check with a bind mount: `mount --bind / /mnt/root && du -sh /mnt/root/var`.
2. ext4 **reserved blocks** (5% for root): `tune2fs -l /dev/X | grep -i reserved`.
3. **Inode exhaustion**: `df -i` at 100% with free space. Millions of small files (session dirs, mail queue).
4. Filesystem metadata/journal, XFS preallocation, sparse files (`du --apparent-size` vs `du`).
5. Snapshots (LVM thin, btrfs) or container overlay layers.

## File descriptor limits ("Too many open files")

| Error | Meaning | Limit |
|---|---|---|
| `EMFILE` | **Per-process** limit hit | `ulimit -n` (RLIMIT_NOFILE soft/hard), `cat /proc/PID/limits` |
| `ENFILE` | **System-wide** limit hit | `fs.file-max`, current usage in `/proc/sys/fs/file-nr` |
| — | Max a hard limit can be raised to | `fs.nr_open` |

**Classic trap:** raising `nofile` in `/etc/security/limits.conf` does **nothing for systemd services**. That file is applied by `pam_limits` at login. For services:
```bash
systemctl edit myapp       # [Service]
                           # LimitNOFILE=65536
systemctl daemon-reload && systemctl restart myapp
cat /proc/$(systemctl show -p MainPID --value myapp)/limits | grep 'open files'
ls /proc/PID/fd | wc -l    # current usage
```
Also check for an **fd leak**: count growing over time = code not closing sockets/files. `lsof -p PID | awk '{print $5}' | sort | uniq -c` shows which type (REG, IPv4, sock, FIFO) is leaking.

## Illusions: /proc and /sys

- **procfs** and **sysfs** are pseudo-filesystems: nothing is on disk. Each `read()` calls a kernel function that generates the content right then. That's why `ls -l /proc/cpuinfo` shows **size 0** but `cat` prints content (size isn't known until it's generated).
- `/proc` = process info + legacy kernel knobs (`/proc/sys` = sysctl). `/sys` = kernel object model (devices, drivers, cgroups at `/sys/fs/cgroup`), one value per file.
- Tools like `ps`, `top`, `free`, `lsof`, `ss` are just `/proc` readers. Knowing the raw files means you can debug inside minimal containers that have no tools.

**Per-process files you should know cold:**

| File | Use |
|---|---|
| `/proc/PID/status` | State, PPid, Threads, VmRSS, Sig masks, Cap* (capabilities), voluntary/nonvoluntary ctxt switches |
| `/proc/PID/cmdline`, `environ` | Args and env (NUL separated: `tr '\0' ' ' < …`) |
| `/proc/PID/fd/`, `fdinfo/` | Open files, offsets, flags |
| `/proc/PID/maps`, `smaps_rollup` | Memory mappings and PSS |
| `/proc/PID/limits` | Effective rlimits (truth vs what you configured) |
| `/proc/PID/stack`, `wchan` | Kernel stack / wait channel (where it's blocked) |
| `/proc/PID/cgroup`, `ns/` | Which cgroup / namespaces it's in |
| `/proc/PID/io` | read_bytes/write_bytes actually hitting storage |
| `/proc/PID/exe`, `cwd`, `root` | Symlinks, `exe` works even if the binary was deleted/upgraded |

System-wide: `/proc/meminfo`, `/proc/loadavg`, `/proc/pressure/*`, `/proc/interrupts`, `/proc/net/*`, `/proc/mounts`, `/proc/sys/kernel/*`.

## Black holes: /dev/null and friends

| Device | Major,minor | Behaviour |
|---|---|---|
| `/dev/null` | 1,3 | Writes discarded and succeed; reads return EOF |
| `/dev/zero` | 1,5 | Reads return infinite zero bytes |
| `/dev/full` | 1,7 | Writes fail with ENOSPC, great for testing how an app handles a full disk |
| `/dev/random`, `/dev/urandom` | 1,8 / 1,9 | Since kernel 5.6, both are non-blocking once the CSPRNG is initialised |

**Production incident:** someone runs `rm /dev/null` or a script does `mv file /dev/null` as root → `/dev/null` becomes a regular file and starts filling `/dev` (tmpfs), and cron jobs break. Fix:
```bash
rm -f /dev/null; mknod -m 666 /dev/null c 1 3; ls -l /dev/null   # crw-rw-rw- 1,3
```
(Or reboot. devtmpfs/udev recreates it.)

## "umount: target is busy"

```bash
fuser -vm /data          # processes using the mount (cwd, open files, mmaps)
lsof +f -- /data
umount -l /data          # lazy: detach now, clean up when last user leaves (use with care)
```
Also a shell whose cwd is inside, an NFS client stuck in D state, or a bind mount / container using it.

## Lab

```bash
# Ghost file
dd if=/dev/zero of=/tmp/ghost bs=1M count=500
tail -f /tmp/ghost > /dev/null & PID=$!
rm /tmp/ghost; df -h /tmp; lsof +L1 | grep ghost
FD=$(ls -l /proc/$PID/fd | awk '/ghost/{print $9}'); : > /proc/$PID/fd/$FD; df -h /tmp; kill $PID

# Size-0 illusion
ls -l /proc/cpuinfo; wc -c /proc/cpuinfo

# /dev/full
echo hi > /dev/full     # "No space left on device"

# fd limit
bash -c 'ulimit -n 20; for i in $(seq 1 30); do exec {fd}</etc/hosts || break; done'
```

## Interview questions

1. **Disk is 100% full but `du` shows 40%. Walk me through it.** deleted-open files → `lsof +L1` → truncate via `/proc/PID/fd` → fix logrotate. Then mention the mount-point and reserved-block causes.
2. **What's in an inode? Where's the filename?** Metadata + block map. The name lives in the directory's dentry.
3. **Hard link vs soft link?** Hard = another name for the same inode (same fs, no dirs). Soft = a file containing a path (can dangle, cross fs).
4. **Raised nofile in limits.conf, app still fails with "Too many open files". Why?** It's a systemd service. Use `LimitNOFILE`. Verify in `/proc/PID/limits`.
5. **Why is /proc/cpuinfo size 0?** Generated on read, so the size isn't known in advance.
6. **How do you debug a process in a distroless container with no `ps`?** Read `/proc` directly, or `nsenter` from the node, or `oc debug` / ephemeral debug container sharing the process namespace.
