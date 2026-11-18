# 05 – cgroups and Namespaces ("Prisoners" and "Parallel universes")

> **A container is just a process** with: namespaces (what it can *see*) + cgroups (what it can *use*) + capabilities/seccomp/SELinux (what it can *do*) + an overlay root filesystem. This one sentence is the bridge from Linux admin to OpenShift engineer.

## Prisoners: cgroups

### v1 vs v2
- **v1**: separate hierarchy per controller (`/sys/fs/cgroup/memory/…`, `/sys/fs/cgroup/cpu,cpuacct/…`). RHEL 8 default.
- **v2**: single unified hierarchy at `/sys/fs/cgroup`. RHEL 9 default; OpenShift 4.14+ new clusters default to v2. Check: `stat -fc %T /sys/fs/cgroup` → `cgroup2fs`.
- v2 rules: processes live only in **leaf** cgroups ("no internal processes"); controllers enabled for children via `cgroup.subtree_control`.

### Key v2 files

| File | Purpose |
|---|---|
| `cgroup.procs` | PIDs in this cgroup (write a PID to move it) |
| `cgroup.controllers` / `cgroup.subtree_control` | Available / enabled for children |
| `cpu.max` | `quota period`, e.g. `50000 100000` = 0.5 CPU (CFS bandwidth) |
| `cpu.weight` | Relative share (1–10000, default 100) when CPUs are contended |
| `cpu.stat` | `nr_throttled`, `throttled_usec`: **throttling evidence** |
| `memory.max` / `memory.high` / `memory.low` / `memory.min` | Hard limit (OOM) / throttle / soft protection / hard protection |
| `memory.current`, `memory.events`, `memory.stat` | Usage, oom/oom_kill counters, breakdown (anon vs file) |
| `io.max`, `io.weight` | Block I/O limits |
| `pids.max`, `pids.current` | Fork-bomb protection |
| `cpuset.cpus`, `cpuset.mems` | CPU pinning / NUMA (HPC, telco, OpenShift performance profiles) |
| `cgroup.freeze`, `cgroup.kill` | Freeze / kill every process in the cgroup |

### systemd owns the tree
```
/sys/fs/cgroup
├── init.scope                  (PID 1)
├── system.slice/               (services: sshd.service, crio.service, kubelet.service …)
├── user.slice/user-1001.slice/ (login sessions)
├── machine.slice/              (VMs, podman containers)
└── kubepods.slice/             (K8s with systemd cgroup driver)
    ├── kubepods-burstable.slice/kubepods-burstable-pod<UID>.slice/crio-<ctr-id>.scope
    └── kubepods-besteffort.slice/…
```
```bash
systemd-cgls                      # tree
systemd-cgtop                     # top by cgroup (CPU, mem, tasks, I/O)
systemctl set-property httpd.service CPUQuota=50% MemoryMax=1G   # persistent
systemd-run --scope -p MemoryMax=200M -p CPUQuota=20% cmd         # ad-hoc
cat /proc/PID/cgroup              # which cgroup a process is in
```
**Why systemd can always stop a service cleanly:** every child a service forks stays in the service's cgroup, even double-forked daemons. `KillMode=control-group` kills all of them. (That's why you can't escape a unit by daemonising.)

### CPU throttling: the most important cgroup interview topic
- K8s `resources.limits.cpu: 1` → `cpu.max = 100000 100000` → 100 ms of CPU time per 100 ms period, **summed across all threads**.
- A 16-thread JVM doing GC can burn the 100 ms quota in ~6 ms of wall time, then is **throttled for the remaining ~94 ms**, even if the node is idle. Result: p99 latency spikes, health-check timeouts.
- Evidence: `cat /sys/fs/cgroup/…/cpu.stat` → `nr_throttled` rising; Prometheus `container_cpu_cfs_throttled_periods_total`.
- Fixes: raise/remove CPU limit (keep requests), right-size thread pools (`-XX:ActiveProcessorCount`), or use static CPU manager for Guaranteed pods.
- `requests.cpu` maps to `cpu.weight` (share under contention). Limits map to `cpu.max` (hard cap).

## Parallel universes: namespaces

| Namespace | Isolates | Flag |
|---|---|---|
| mnt | Mount table | `CLONE_NEWNS` |
| uts | hostname, domainname | `CLONE_NEWUTS` |
| ipc | SysV IPC, POSIX mqueues | `CLONE_NEWIPC` |
| pid | PID numbers (container sees itself as PID 1) | `CLONE_NEWPID` |
| net | Interfaces, routes, iptables, sockets, ports | `CLONE_NEWNET` |
| user | UID/GID mapping (root inside, unprivileged outside) | `CLONE_NEWUSER` |
| cgroup | View of the cgroup tree | `CLONE_NEWCGROUP` |
| time | CLOCK_MONOTONIC/BOOTTIME offsets (5.6+) | `CLONE_NEWTIME` |

- Created by `clone()`/`unshare()`, joined by `setns()`. Represented as `/proc/PID/ns/*` symlinks (inode number = identity).
- A namespace lives while a process is in it or something holds it open (bind-mounted `/run/netns/X`, an open fd). This is how the K8s **pause container** holds the pod's net namespace while app containers restart.
- PID namespaces nest: the host sees the container process with a normal PID; inside it's PID 1. `grep NSpid /proc/PID/status` shows both.

```bash
lsns                                   # all namespaces and their owning process
lsns -t net
ls -l /proc/$$/ns
sudo unshare --pid --fork --mount-proc --uts --net bash   # mini-container
#   inside: ps aux (only 2 procs), hostname test, ip a (only lo, down)
```

### Debugging a container from the node (OpenShift/K8s skill)
```bash
oc debug node/<node>; chroot /host
crictl ps | grep <pod>
PID=$(crictl inspect <ctr-id> | jq .info.pid)
nsenter -t $PID -n ip a                     # container's network view with host tools
nsenter -t $PID -n ss -tlnp
nsenter -t $PID -n tcpdump -i eth0 -nn port 8080
nsenter -t $PID -m -u -i -n -p -- sh        # full "exec" without kubectl
cat /proc/$PID/cgroup; cat /sys/fs/cgroup/$(awk -F: '{print $3}' /proc/$PID/cgroup)/memory.events
```

## Capabilities, seccomp, SELinux (the third pillar)
- Root's powers split into ~40 **capabilities** (`CAP_NET_ADMIN`, `CAP_SYS_ADMIN`, `CAP_NET_BIND_SERVICE`, `CAP_SYS_PTRACE`…). `grep Cap /proc/PID/status`, `capsh --decode=<hex>`, `getpcaps PID`.
- **seccomp** filters which syscalls are allowed (`RuntimeDefault` profile).
- **SELinux** on OpenShift: every container runs as `container_t` with unique **MCS categories** (`s0:c26,c5`) so container A can't read container B's files even if both run as the same UID.
- OpenShift **SCC `restricted-v2`**: random high UID from the namespace range, drops ALL caps, no privilege escalation, seccomp RuntimeDefault. Why images that need root or write to `/` fail on OpenShift but work on plain Docker.

## Lab

```bash
# CPU throttling demo
sudo systemd-run --unit=burn -p CPUQuota=20% sh -c 'while :; do :; done'
sleep 10; cat /sys/fs/cgroup/system.slice/burn.service/cpu.stat; top -b -n1 | head -15
sudo systemctl stop burn

# Namespace sandbox
sudo unshare --pid --fork --mount-proc bash -c 'echo "I am PID $$"; ps aux'

# Find a podman container's namespaces from the host
podman run -d --name web registry.access.redhat.com/ubi9/ubi sleep 1000
PID=$(podman inspect -f '{{.State.Pid}}' web); lsns -p $PID; sudo nsenter -t $PID -u hostname
podman rm -f web
```

## Interview questions

1. **What is a container, from the kernel's point of view?** Process + namespaces + cgroups + capabilities/seccomp/LSM + overlay rootfs. No "container" object exists in the kernel.
2. **Pod has CPU limit 2, node is 20% used, but the app is slow. Why?** CFS quota throttling. Show `cpu.stat` evidence and the fix.
3. **requests vs limits at the cgroup level?** requests → `cpu.weight` (and scheduling); limits → `cpu.max` / `memory.max`.
4. **How does the pod keep its IP when a container restarts?** The pause/infra container holds the net namespace.
5. **How do you capture packets of one pod?** `nsenter -t <pid> -n tcpdump` from the node, or `oc debug` with the pod's netns.
6. **Why does an image run with Docker but crash on OpenShift?** Random UID + restricted SCC + SELinux. Fix the image (group 0 permissions, no privileged ports), don't grant `anyuid` blindly.
