# 07 – Networking and Firewall ("Bouncers")

## netfilter: where the bouncers stand

```
            ┌──────────── local process ────────────┐
            │ INPUT                          OUTPUT │
 NIC → PREROUTING → routing decision ──┤                        ├─→ POSTROUTING → NIC
                                       └──────── FORWARD ───────┘
```
- **Hooks:** PREROUTING (DNAT happens here), INPUT (to local sockets), FORWARD (routed through: K8s nodes, routers), OUTPUT (locally generated), POSTROUTING (SNAT/masquerade).
- **iptables tables:** `raw` (conntrack bypass), `mangle`, `nat`, `filter`, `security`. **nftables** replaces them with user-defined tables/chains attached to the same hooks.
- RHEL 8/9: `iptables` command is **iptables-nft** (rules land in nftables). `firewalld` is a zone-based manager on top of nftables. Don't mix raw `nft` edits with firewalld unless you know the ownership.

```bash
nft list ruleset
firewall-cmd --get-active-zones ; firewall-cmd --list-all --zone=public
firewall-cmd --add-port=8443/tcp            # runtime only (lost on reload)
firewall-cmd --runtime-to-permanent         # or use --permanent + --reload
iptables-save | head                         # legacy view
```

### DROP vs REJECT (great diagnostic question)
| Client sees | Meaning |
|---|---|
| **Timeout** (SYN retransmits, hangs ~2 min) | Packet **dropped** by a firewall (host, SG, network), or routing black hole |
| **Connection refused** instantly | Host reachable, **no listener** on that port (kernel sends RST), or a firewall **REJECT** with tcp-reset |
| **No route to host** | ICMP host-unreachable: firewall REJECT (`icmp-host-prohibited`, firewalld default) or ARP failure |

## conntrack: the stateful memory of the bouncer

- Every flow (even UDP/ICMP) gets a conntrack entry. NAT and `ct state established,related accept` depend on it. kube-proxy (iptables/IPVS mode) relies heavily on it.
- **Table full:** `nf_conntrack: table full, dropping packet` in `dmesg` → random new-connection drops under load, existing ones fine. Very common on busy K8s nodes, load balancers, DNS servers.
```bash
sysctl net.netfilter.nf_conntrack_count net.netfilter.nf_conntrack_max
conntrack -S                     # insert_failed, drop, early_drop counters
conntrack -L | awk '{print $4}' | sort | uniq -c | sort -rn | head   # by state
```
Fix: raise `nf_conntrack_max` (and hashsize), lower timeouts (`nf_conntrack_tcp_timeout_time_wait`), `NOTRACK` in raw table for high-volume stateless traffic (e.g. DNS).
- UDP conntrack race (DNS 5-second delays in K8s): parallel A/AAAA queries from the same socket → `insert_failed`. Mitigations: `single-request-reopen`, NodeLocal DNSCache.

## TCP states you must be able to explain

| State | Who | Meaning / problem |
|---|---|---|
| `LISTEN` | server | Waiting. `ss -lnt` Recv-Q = current accept queue, Send-Q = backlog max |
| `SYN-RECV` | server | Half-open. Thousands → SYN flood or slow app accept (`tcp_syncookies`) |
| `ESTABLISHED` | both | Normal |
| `TIME_WAIT` | **active closer** | 60s (2×MSL on Linux). Thousands are normal on clients/proxies. Ephemeral port exhaustion if too many to the same dest (`ip_local_port_range`, `tcp_tw_reuse`, connection pooling) |
| `CLOSE_WAIT` | passive side | Remote closed, **our app hasn't called close()**. Growing count = **application bug** (fd/socket leak), not a kernel tuning issue |
| `FIN-WAIT-2` | active closer | Waiting for remote's FIN |

```bash
ss -s                                     # summary by state
ss -tan state close-wait | wc -l
ss -tnp state established '( dport = :5432 )'
ss -lnt                                   # accept queue: Recv-Q near Send-Q = app not accepting fast enough
nstat -az | grep -iE 'ListenOverflows|ListenDrops|TCPRetrans|TCPTimeouts'
netstat -s | grep -i -E 'overflow|SYNs to LISTEN'
```
**Accept queue overflow:** backlog = min(app's `listen()` backlog, `net.core.somaxconn`). App is busy (GC, thread pool exhausted), queue fills, new SYNs/ACKs dropped → client timeouts while the server "looks fine".

## Packet-path troubleshooting order

1. Is the service listening, on which IP? `ss -tlnp | grep 8080` (bound to 127.0.0.1 vs 0.0.0.0 is a classic).
2. Local firewall? `nft list ruleset`, `firewall-cmd --list-all`.
3. Routing: `ip route get <dst>`, `ip rule`, asymmetric routing + `rp_filter=1` silently drops replies (multi-homed servers).
4. Did the packet arrive? `tcpdump -i any -nn host X and port Y`. SYN in and no SYN-ACK out = local drop; SYN-ACK out and no ACK in = return path.
5. ARP/neighbour: `ip neigh`. MTU: `ping -M do -s 1472 dst` (overlay networks like VXLAN/Geneve reduce MTU, causing big packets to hang, typically TLS handshakes or large POSTs).
6. SELinux denials for non-standard ports: `ausearch -m avc -ts recent`, `semanage port -l`.
7. DNS: `dig`, `/etc/resolv.conf`, `ndots:5` in pods causing extra lookups.

## OpenShift / Kubernetes tie-in
- kube-proxy iptables mode: Service ClusterIP → DNAT chains (`KUBE-SERVICES`, `KUBE-SVC-*`, `KUBE-SEP-*`) with random probability load balancing.
- **OVN-Kubernetes** (OpenShift default): services and network policy implemented in OVS flows via OVN, not iptables. Debug with `ovn-nbctl`/`ovs-ofctl dump-flows`, `oc adm must-gather`, and `ovnkube-trace`.
- NetworkPolicy deny looks like a **DROP** (timeout), not refused.

## Lab

```bash
# DROP vs REJECT
python3 -m http.server 8080 &
sudo nft add table inet lab
sudo nft add chain inet lab input '{ type filter hook input priority -10; }'
sudo nft add rule inet lab input tcp dport 8080 iifname != lo drop
# from another host: curl -m5 http://<vm-ip>:8080  → timeout
sudo nft flush chain inet lab input
sudo nft add rule inet lab input tcp dport 8080 iifname != lo reject with tcp reset
# from another host → connection refused instantly
sudo nft delete table inet lab; kill %1

# CLOSE_WAIT leak (server accepts, never closes)
python3 - <<'EOF' &
import socket,time
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(("127.0.0.1",9000)); s.listen()
conns=[s.accept()[0] for _ in range(5)]; time.sleep(120)
EOF
sleep 1; for i in 1 2 3 4 5; do timeout 1 bash -c 'exec 3<>/dev/tcp/127.0.0.1/9000; exec 3>&-'; done
ss -tan state close-wait '( sport = :9000 )'
```

## Interview questions

1. **Client gets a timeout vs connection refused. What does each tell you?** See the DROP vs REJECT table.
2. **Thousands of CLOSE_WAIT on the app server. Tune the kernel?** No, it's an app bug. Explain why.
3. **Thousands of TIME_WAIT. Problem?** Usually not. Only if ports to one destination are exhausted; then pooling or keep-alive.
4. **Random connection drops under peak load on a K8s node, no app errors.** conntrack table full / accept queue overflow. Show the evidence commands.
5. **Walk a packet from a pod to a Service IP.** pod netns → veth → node → DNAT (iptables or OVN flow) to an endpoint → routed/tunnelled (Geneve) to the target node → target pod netns.
