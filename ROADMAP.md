# PROJECT AROHAN AI — Roadmap

Where AROHAN is going, in what order, and what has to be proven before each step. What exists today is the status table in the [README](README.md#whats-actually-here-status); how work is judged is in [standards/](standards/README.md).

The roadmap is **capability-driven, not date-driven**: a stage moves forward only when the previous one has evidence.

---

## 1. The five stages

| # | Stage | Core capabilities | Transition |
|---|---|---|---|
| 1 | **Platform Engineering** | Linux, Kubernetes, OpenShift, containers, Helm, Terraform, Ansible, GitOps / Argo CD, observability, security, reliability | Manual infrastructure → declarative, automated platform |
| 2 | **AI Infrastructure** | GPU infrastructure and scheduling, multi-GPU and distributed AI, model serving and inference, AI-aware resource management | Platform → infrastructure engineered for AI workloads, not treated as generic apps |
| 3 | **AI Operations** | Metrics, logs, traces, events, GPU telemetry, SLI/SLO and error budgets, incident response, AI-assisted RCA, capacity intelligence, FinOps | Monitoring → operational understanding |
| 4 | **Autonomous Operations (guarded)** | Decision engines, policy enforcement, guarded remediation, automated RCA, recovery verification | Understanding → controlled, policy-checked action |
| 5 | **Autonomous AI Factory** | Multi-tenant AI platforms, GPU orchestration, predictive operations, self-healing, multi-agent operations, policy-driven autonomy | Controlled autonomy → end-to-end governed AI platform operations |

**You are here:** Stage 1, moving into Stage 2.

---

## 2. Current focus

| Priority | Work | Done when |
|---|---|---|
| 1 | OpenShift and Kubernetes platform depth ([workload management plan](engineering/workload-management/MASTERY_PLAN.md), Phase 1) | Lab write-ups with evidence for node config, networking and scheduling |
| 2 | [Lab 03: GPU scheduling](labs/03-gpu-scheduling/README.md) (`kind` + fake GPUs, no cloud cost) | Run end to end, evidence captured, status ✅ |
| 3 | [Lab 02: AI inference reliability](labs/02-ai-inference-reliability/README.md) | Run end to end, evidence captured, status ✅ |
| Ongoing | [Workload management topics](engineering/workload-management/README.md) (twice a week) and [AI-infra notes](engineering/notes/README.md) (weekly) | Notes merged with sources |

---

## 3. How autonomy is earned

AROHAN does not treat an AI agent with infrastructure access as autonomous engineering. Each step depends on the one before it:

**Observe → Understand → Automate → Detect → Diagnose → Recommend → Guard → Remediate → Verify → Learn → Predict → Optimize**

The target operating loop (Stage 4):

**Observe → Detect → Diagnose → Decide → Guardrail → Remediate → Verify → Explain (RCA) → Notify → Audit**

> **The AI agent proposes and reasons. Policy decides what the agent is allowed to execute. Verification decides whether it worked.**

Autonomous actions must be explicitly allowed, policy-controlled, auditable, reversible where possible, and verified after execution.

### Gates

A capability does not move up until each question has an evidenced "yes":

| Gate | Question |
|---|---|
| 1 Observability | Can we reliably observe the system? |
| 2 Diagnosis | Can we explain why something happened? |
| 3 Automation | Can we execute the remediation reliably? |
| 4 Guardrails | Can we restrict what automation is allowed to do? |
| 5 Verification | Can we prove the action worked? |
| 6 Explainability | Can we explain why the decision was made? |
| 7 Auditability | Can we reconstruct what happened? |
| 8 Autonomy | Can the system safely run the whole loop? |

### Autonomy levels

| Level | Name | Operating model |
|---|---|---|
| L0 | Manual | Engineer operates the infrastructure |
| L1 | Automated | Scripts run known procedures |
| L2 | Observable | Behaviour is measurable |
| L3 | Intelligent | AI assists detection, diagnosis and decisions |
| L4 | Guarded autonomous | Policy-controlled automated action |
| L5 | Predictive | Risks and demand are predicted |
| L6 | Optimizing | Infrastructure continuously optimizes itself |
| L7 | Multi-agent | Specialized agents coordinate operations |
| L8 | Autonomous AI Factory | End-to-end governed autonomous operations |

Lab-level maturity (implement → observe → validate → break → recover …) is a separate scale, defined in the [standards](standards/README.md#lab-lifecycle-and-maturity).

---

## 4. The plan after the current focus

| When | Milestone | Key capabilities | Completion gate |
|---|---|---|---|
| **Next** | Autonomous operations foundation (Kubernetes) | AI-powered RCA, guarded remediation, recovery verification, policy-controlled actions, audit trail | One controlled incident runs end to end: incident → detection → evidence collection → AI diagnosis → policy check → remediation → verification → RCA → notification → audit |
| **Then** | Autonomous AI operations | GPU health, anomaly detection and remediation; inference and model-serving incidents; incident correlation; automated RCA; notification routing | AI-infrastructure incidents are detectable, diagnosable, policy-evaluable and safely recoverable |
| **Later** | Predictive operations | Failure, capacity, GPU-demand and cost forecasting; saturation and anomaly prediction | Historical and live signals identify real risks before they become incidents |
| **Later** | Autonomous optimization | GPU utilization, placement, right-sizing, queue, scheduling and energy-aware optimization | Every optimization is measurable, policy-controlled, reversible where practical and verified |
| **Future** | Multi-agent operations | Kubernetes, GPU, SRE, security, FinOps, capacity and RCA agents under a policy/governance layer | Agents stay policy-governed, least-privilege, observable, explainable and auditable |
| **Vision** | Autonomous AI Factory | Compute, Kubernetes, GPU, networking, storage, AI workloads, observability, SRE, security, FinOps and AIOps as one governed platform | Infrastructure can observe, predict, decide, act, verify and learn, within explicit policy |

---

## 5. Roadmap principles

1. Build before claiming; every major capability needs evidence ([Definition of Done](standards/README.md#definition-of-done)).
2. Solve real infrastructure problems, not demos.
3. Foundations before autonomy: observability precedes intelligence, automation precedes autonomy.
4. Policy and guardrails precede autonomous execution; verification follows every automated action.
5. Security, governance and cost are engineering concerns at every stage.

Roadmap items use the repository [status model](standards/README.md#status-model): ✅ completed · 🔵 implemented · 🟢 in progress · 🟡 planned · ⚪ future.

---

> **The goal is not more automation. It is controlled, explainable, policy-governed autonomy, earned one evidenced step at a time.**
