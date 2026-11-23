# AROHAN Lab 06: eBPF for Kubernetes and OpenShift. Networking, flow visibility and runtime security around AI workloads

## Status

**LAB 06: PLANNED 🟡 (runbook ready, not yet run)** (eBPF tracing basics: [Linux internals 04](../../engineering/linux-internals/04-tracing-and-debugging.md) · tracing depth: [kernel troubleshooting roadmap, Phase 8](../../engineering/kernel-troubleshooting/ROADMAP.md) · GPU side: [Lab 04](../04-gpu-infra-hands-on/README.md))

**Project:** AROHAN AI · Platform observability and security track
**Platform:** `kind` or K3s on a GCP CPU VM (Exercises 1–3, 5, 6, 8); an OpenShift lab cluster (Exercise 4); one short GPU session reusing Lab 04's L4 VM (Exercise 7)
**Time:** about 20–24 hours across 8 exercises
**Budget:** about **USD 5–10** (≈ ₹500–1,000) on Spot VMs, plus any OpenShift lab you already have

> Goal: use eBPF at the **platform** level — kernel-native networking, flow visibility and runtime security on Kubernetes and OpenShift — and learn to correlate host-side eBPF signals with GPU-side DCGM signals when an AI workload misbehaves.
>
> **Honesty note:** commands are written from project documentation and have **not yet been run end to end**. Chart values, flags and rule names change between releases; steps marked *check the docs* need confirming first. The first run is the validation; record differences in `evidence/`.

**What this lab does not repeat:** eBPF for ad-hoc node troubleshooting (bcc tools, bpftrace one-liners, ftrace) is covered in [Linux internals 04](../../engineering/linux-internals/04-tracing-and-debugging.md) and [roadmap Phase 8](../../engineering/kernel-troubleshooting/ROADMAP.md); GPU telemetry and DCGM are [Lab 04](../04-gpu-infra-hands-on/README.md).

---

## Key idea: eBPF sees the host, DCGM sees the GPU

eBPF programs run in the Linux kernel. They see syscalls, scheduling, memory, block I/O and every packet — but **not** what happens inside the GPU. GPU utilisation, memory, throttling and Xid errors come from DCGM/NVML. Production debugging of AI workloads combines both:

| Symptom | eBPF tells you | DCGM tells you |
|---|---|---|
| Inference latency spike | Network retransmits, run-queue delay, slow syscalls, dropped flows | GPU utilisation, throttling, memory pressure |
| Training job slow | NCCL traffic drops, CPU starvation of data loaders | GPU idle time, PCIe/NVLink activity |
| Suspicious pod | Unexpected process, file write, outbound connection | — |

---

## Upstream ↔ OpenShift mapping

| Capability | Upstream (this lab) | OpenShift equivalent |
|---|---|---|
| Pod networking and policy | Cilium (eBPF datapath, kube-proxy replacement) | OVN-Kubernetes (default); Cilium available as a certified third-party CNI |
| Flow visibility | Hubble | Network Observability Operator (eBPF agent → Loki / Prometheus, console plug-in) |
| Runtime security | Falco, Tetragon | Red Hat Advanced Cluster Security (eBPF-based collector, runtime policies) |
| Ad-hoc node tracing | bpftrace / bcc on the node | Same tools via `oc debug node/<n>` + `toolbox` |

---

## Exercise map

| # | Exercise | Where | Hours | Approx. cost |
|---|---|---|---|---|
| 1 | eBPF fundamentals on a node | CPU VM | 2 | < $1 |
| 2 | Cilium datapath and network policies | `kind` on CPU VM | 4 | ~$1 |
| 3 | Hubble flow visibility and drop analysis | same | 3 | ~$1 |
| 4 | OpenShift Network Observability Operator | OpenShift lab cluster | 3 | — |
| 5 | Runtime security with Falco (and Tetragon) | `kind` / K3s | 4 | ~$1 |
| 6 | Incident drill: slow service, network or node? | same | 3 | < $1 |
| 7 | eBPF + DCGM correlation on a GPU inference node | Lab 04 L4 VM | 2 | ~$2 |
| 8 | Overhead, kernel requirements and safety | CPU VM | 2 | < $1 |

---

## Exercise 1 — eBPF fundamentals on a node

1. On an Ubuntu 22.04/24.04 or Rocky 9 VM, check kernel support:
   ```bash
   uname -r
   ls -l /sys/kernel/btf/vmlinux          # BTF present → CO-RE programs can run
   sudo bpftool feature probe | head -40
   ```
2. See what eBPF is already loaded (systemd, the container runtime and security agents often load programs):
   ```bash
   sudo bpftool prog list
   sudo bpftool map list
   ```
3. Load your own: run a bpftrace one-liner in one terminal and inspect it from another with `bpftool prog list` — note program type (kprobe, tracepoint), the verifier, and the maps it created.
   ```bash
   sudo bpftrace -e 'tracepoint:syscalls:sys_enter_openat { @[comm] = count(); }'
   ```
4. Write the concept map: program types (kprobe/uprobe, tracepoint, XDP, tc, cgroup, LSM), maps, the verifier, BTF/CO-RE, and which type each tool in this lab uses.

**Evidence:** `bpftool` outputs before/after, concept map.

---

## Exercise 2 — Cilium datapath and network policies

1. `kind` cluster without the default CNI or kube-proxy:
   ```yaml
   # kind-cilium.yaml
   kind: Cluster
   apiVersion: kind.x-k8s.io/v1alpha4
   nodes: [{role: control-plane}, {role: worker}, {role: worker}]
   networking:
     disableDefaultCNI: true
     kubeProxyMode: none
   ```
   ```bash
   kind create cluster --config kind-cilium.yaml
   ```
2. Install Cilium with the CLI as the kube-proxy replacement (*check the Cilium docs for the current kind values*), then verify:
   ```bash
   cilium install --set kubeProxyReplacement=true
   cilium status --wait
   cilium connectivity test
   ```
3. Deploy a two-tier app (frontend → backend) and apply policies in steps: default-deny, allow frontend → backend on TCP 8080, then an **L7** `CiliumNetworkPolicy` allowing only `GET /api/*`.
4. Inspect the datapath on a node: `kubectl -n kube-system exec ds/cilium -- cilium-dbg bpf lb list` (services implemented as eBPF maps, no iptables) and compare `iptables-save | wc -l` with a kube-proxy cluster.

**Evidence:** connectivity test result, each policy's allowed/denied curl output, service map listing.

---

## Exercise 3 — Hubble flow visibility and drop analysis

1. Enable Hubble and its UI, then port-forward the relay:
   ```bash
   cilium hubble enable --ui
   cilium hubble port-forward &
   hubble status
   ```
2. Observe live traffic and filter:
   ```bash
   hubble observe --namespace demo --follow
   hubble observe --verdict DROPPED --follow
   hubble observe --protocol http --http-status 403
   ```
3. Break things on purpose: tighten a policy so the backend call fails, make DNS fail with a wrong egress rule. Find each failure from Hubble alone — source, destination, verdict and the policy responsible.
4. Open the Hubble UI service map and export a screenshot.

**Evidence:** `hubble observe` output for each drill, service-map screenshot, short RCA per drill.

---

## Exercise 4 — OpenShift Network Observability Operator

On an OpenShift lab cluster (OVN-Kubernetes):

1. Install the **Network Observability Operator** from OperatorHub (and the Loki Operator, or use the Prometheus-only mode — *check the docs for "without Loki"*).
2. Create the `FlowCollector` named `cluster`; confirm the eBPF agent DaemonSet:
   ```bash
   oc get flowcollector cluster
   oc get pods -n netobserv-privileged    # eBPF agent pods (namespace per docs)
   ```
3. Enable the optional agent features (*check the docs for names and prerequisites*): packet drops (privileged agent), DNS tracking, flow round-trip time, and network events for NetworkPolicy/AdminNetworkPolicy decisions.
4. Repeat Exercise 3's drills with OpenShift `NetworkPolicy`; find the drops and the policy verdicts in the console's **Observe → Network Traffic** view.
5. Write the Hubble ↔ Network Observability comparison: data source, storage, UI, policy visibility, overhead.

**Evidence:** FlowCollector status, console screenshots (topology, drops), comparison table.

---

## Exercise 5 — Runtime security with Falco (and Tetragon)

1. Install Falco with the modern eBPF probe:
   ```bash
   helm repo add falcosecurity https://falcosecurity.github.io/charts && helm repo update
   helm install falco falcosecurity/falco -n falco --create-namespace \
     --set driver.kind=modern_ebpf --set tty=true
   kubectl -n falco logs ds/falco -f
   ```
2. Trigger detections from a test pod and read each alert:
   - interactive shell: `kubectl exec -it <pod> -- sh`
   - write under `/etc` inside the container
   - read a sensitive file such as `/etc/shadow`
   - unexpected outbound connection to an external IP
   Note which default rule fired for each (*rule names change between releases*).
3. Write one custom rule (e.g. any process named like a crypto miner, or a shell inside an inference namespace) and prove it fires.
4. Optional: install Tetragon and apply a `TracingPolicy` that not only detects but **blocks** a write to a protected path; compare detect-only (Falco) with enforce (Tetragon).
5. Map each detection to an **RHACS** runtime policy (shell in container, sensitive file access, unexpected network activity) — what RHACS adds: policy management, image vulnerability context, admission control.

**Evidence:** alert lines per trigger, custom rule + proof, Falco/Tetragon/RHACS comparison.

---

## Exercise 6 — Incident drill: slow service, network or node?

1. On the Cilium cluster, run a simple HTTP service and a steady load (e.g. `hey` or a curl loop) and record baseline p99 latency.
2. Inject faults one at a time, without telling yourself which (script random choice):
   - network delay/loss on the backend node: `tc qdisc add dev eth0 root netem delay 80ms loss 2%`
   - CPU starvation on the backend node: `stress-ng --cpu 0 --timeout 300`
   - a policy change that drops a fraction of calls
3. Diagnose using only eBPF signals:
   ```bash
   hubble observe --namespace demo --verdict DROPPED
   sudo /usr/share/bcc/tools/tcpretrans        # retransmits (bcc tool path varies by distro)
   sudo /usr/share/bcc/tools/runqlat 5 1        # CPU run-queue delay
   sudo bpftrace -e 'kprobe:tcp_retransmit_skb { @[comm] = count(); }'
   ```
4. Write the RCA in the repo's format: which signal pointed to which cause, and how you ruled the others out.

**Evidence:** baseline vs fault latency, signal outputs per fault, RCAs.

---

## Exercise 7 — eBPF + DCGM correlation on a GPU inference node

Reuse the Lab 04 Exercise 10 L4 VM with Triton and `dcgm-exporter` running.

1. While `perf_analyzer` drives load, collect host-side eBPF signals for the server process — `offcputime -p <tritonserver pid>`, `runqlat`, `tcplife`/`tcpretrans` — and GPU-side `dcgmi dmon -e 155,203,252`.
2. Inject a network delay (as in Exercise 6), then a CPU starvation, then a GPU-side load (a second CUDA process). For each, record which signals move: eBPF, DCGM or both.
3. Write the correlation table and an RCA: "latency up, GPU utilisation down, retransmits up → network, not GPU".

**Evidence:** signal table per fault, RCA. Tear the VM down after the session.

---

## Exercise 8 — Overhead, kernel requirements and safety

1. Measure what eBPF costs: enable runtime statistics and read per-program run time:
   ```bash
   sudo sysctl -w kernel.bpf_stats_enabled=1
   sudo bpftool prog show | grep -E "run_time_ns|run_cnt"
   ```
   Compare node CPU with Cilium/Hubble/Falco on vs off under the Exercise 6 load (`kubectl top`, `mpstat`).
2. Document requirements: minimum kernel features, BTF availability, privileged agents, Secure Boot and lockdown considerations, and how RHCOS kernels fit.
3. Write the production checklist: who may load eBPF programs, how agents are upgraded with the kernel, sampling rates, and data retention for flow logs.

**Evidence:** overhead measurements, requirements and checklist notes.

---

## Interview scenarios this lab prepares you for

| Likely question | Exercise |
|---|---|
| "What is eBPF, and why is it safer than a kernel module?" | 1 |
| "How does Cilium replace kube-proxy, and what changes?" | 2 |
| "A pod can't reach a service. How do you prove it's a network policy?" | 3, 4 |
| "How do you get network flow visibility on OpenShift?" | 4 |
| "How would you detect a shell or a crypto miner in a container?" | 5 |
| "Detection vs enforcement: Falco vs Tetragon vs RHACS?" | 5 |
| "Latency went up — network, CPU or GPU?" | 6, 7 |
| "What does eBPF cost, and what are its risks in production?" | 8 |

## Study material

- Liz Rice, *Learning eBPF* (O'Reilly) — fundamentals and program types
- [ebpf.io](https://ebpf.io) — official documentation and project landscape
- [Cilium documentation](https://docs.cilium.io) and Hubble — datapath, policies, observability
- [Falco documentation](https://falco.org/docs/) and [Tetragon documentation](https://tetragon.io/docs/)
- [OpenShift Network Observability](https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/network_observability/network-observability-overview) and Red Hat Advanced Cluster Security documentation
- Brendan Gregg, *BPF Performance Tools* — already in the [kernel roadmap](../../engineering/kernel-troubleshooting/ROADMAP.md)

## Evidence checklist

- [ ] Ex 1 `bpftool` outputs + concept map
- [ ] Ex 2 Cilium connectivity + L3/L4/L7 policy proofs
- [ ] Ex 3 Hubble drills + RCAs
- [ ] Ex 4 Network Observability on OpenShift + comparison
- [ ] Ex 5 Falco detections, custom rule, Tetragon/RHACS comparison
- [ ] Ex 6 fault drills + RCAs
- [ ] Ex 7 eBPF + DCGM correlation + RCA
- [ ] Ex 8 overhead measurements + production checklist

Status moves to ✅ only when every box has evidence in `evidence/`.
