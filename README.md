# PROJECT AROHAN AI (आरोहण, "ascent")

### A hands-on journey from enterprise Linux operations to AI infrastructure architecture

> **Build it. Break it. Measure it. Document it. Only then automate it.**

AROHAN AI is my long-term, hands-on engineering initiative. It covers how AI workloads are **scheduled, served, observed and kept reliable** on Kubernetes/OpenShift and GPU infrastructure, built as labs with failure injection and evidence rather than as reading notes.

The long-term direction is **governed autonomous operations**: AI-assisted diagnosis where *policy* decides what may be executed and *verification* proves it worked. That is the destination, not the current state. The table below shows exactly what exists today.

---

## What's actually here (status)

| Area | Item | Status |
|---|---|---|
| **Lab 01** | [Workload reliability foundation](labs/01-gpu-workload-reliability/README.md): K3s workload, Prometheus, reliability SLI + alert, controlled failure injection, alert lifecycle and recovery validation | ✅ **Done, with evidence** |
| **Lab 02** | [AI inference reliability](labs/02-ai-inference-reliability/README.md): an LLM (Ollama) on Kubernetes with quotas, probes, benchmarks, failure drills and RCAs | 🟡 Planned, runbook written |
| **Lab 03** | [GPU scheduling](labs/03-gpu-scheduling/README.md): filter/score, taints vs affinity, GPU fragmentation + bin-packing, gang deadlock, NVIDIA KAI Scheduler (kind + fake GPUs) | 🟡 Planned, runbook written |
| Notes | [Kubernetes scheduling, from kube-scheduler to GPU gangs](engineering/gpu-scheduling/KUBERNETES_SCHEDULING_DEEP_DIVE.md) | ✅ Written |
| Notes | [AI inference on Kubernetes: lifecycle and latency](engineering/ai-inference/INFERENCE_ON_KUBERNETES.md) | ✅ Written |
| Notes | [AI-infrastructure notes](engineering/notes/README.md): one topic a week from a 40-topic curriculum, GPU fundamentals to reference architectures | 🟢 Weekly |
| Notes | [NVIDIA AI infrastructure foundations](engineering/NVIDIA/README.md) (prep for the NCA-AIIO certification, which I hold) | ✅ Written |
| Standards | [Engineering standards & principles](standards/README.md) | ✅ In use |
| Next | AI-assisted RCA, policy-guarded remediation, GPU telemetry (DCGM), GPU Operator, FinOps | ⚪ Planned |

**Honest constraints:** labs run on a CPU-only GCP K3s cluster and on `kind` with simulated GPUs. No paid GPU hardware is used. Where a lab needs real GPUs, the README says so.

**Companion repo:** [infra-automation-lab](https://github.com/NookireddiDileep/infra-automation-lab) holds a daily scenario solved in Bash, Ansible, Python and Go.

---

## The journey

```
Platform Engineering → AI Infrastructure → AI Operations → Guarded Autonomy → AI Factory
 (K8s, OpenShift,       (GPU scheduling,     (telemetry, SLOs,  (policy-checked      (end-to-end GPU
  GitOps, observability) serving, inference)  RCA, FinOps)       remediation, verify)  platform operations)
         ▲ you are here (Labs 01–03)
```

Every capability moves through the same gate: **Build → Observe → Understand → Automate → Guard → Verify**. Nothing is marked done without evidence in the lab's `evidence/` folder.

The target control loop, built step by step across labs:

**Observe → Detect → Diagnose → Decide → Policy / Guardrail → Remediate → Verify → RCA → Notify → Audit**

> AI reasons about the situation. Policy decides what AI is allowed to do. Verification decides whether it worked.

More detail: [EVOLUTION.md](EVOLUTION.md) (how autonomy is earned) · [ROADMAP.md](ROADMAP.md) (planned sequence) · [CHANGELOG.md](CHANGELOG.md) (what has actually been implemented).

---

## Domains covered over time

| Domain | Topics |
|---|---|
| Platform | Linux, Kubernetes, OpenShift, containers, Helm, Ansible, GitOps/Argo CD |
| AI infrastructure | GPU scheduling, MIG/time-slicing, KAI/Kueue/Volcano, model serving, inference |
| Observability & SRE | Prometheus, Grafana, OpenTelemetry, SLI/SLO, error budgets, incident response |
| Security | RBAC, least privilege, NetworkPolicy, pod security / SCC, multi-tenancy, AI-agent permissions |
| FinOps | GPU utilization and idle time, cost per workload / request / token |

---

## Repository layout

```
project-arohan-ai/
├── labs/          hands-on labs: README runbook, manifests, scripts, evidence/
├── engineering/   deep-dive notes (scheduling, inference, NVIDIA foundations)
├── standards/     engineering standards and principles
├── CHARTER.md · MISSION.md · EVOLUTION.md · ROADMAP.md · CHANGELOG.md
```

---

## About

Built by **Nookireddi Dileep**, a senior Linux/infrastructure engineer (RHEL, HPC, private cloud) growing into Kubernetes/OpenShift platform engineering and AI infrastructure architecture. Some notes and lab designs are AI-assisted. Lab results and evidence come from my own runs.
