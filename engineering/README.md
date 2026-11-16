# Project AROHAN AI — Engineering

Deep-dive notes and study modules behind the labs. The labs in [`labs/`](../labs/) prove things hands-on; this folder explains the theory they test.

How work is approached and judged: [principles](../standards/ENGINEERING_PRINCIPLES.md) · [standards](../standards/README.md). Where the project is going: [ROADMAP.md](../ROADMAP.md). What exists today: the status table in the [README](../README.md).

## Contents

| Area | What it covers | Used by |
|---|---|---|
| [Kubernetes scheduling deep dive](gpu-scheduling/KUBERNETES_SCHEDULING_DEEP_DIVE.md) | kube-scheduler to GPU gangs: filter/score, fragmentation, gang deadlock, KAI | [Lab 03](../labs/03-gpu-scheduling/README.md) |
| [AI inference on Kubernetes](ai-inference/INFERENCE_ON_KUBERNETES.md) | Request lifecycle and where inference latency goes | [Lab 02](../labs/02-ai-inference-reliability/README.md) |
| [Workload management mastery](workload-management/README.md) | K8s / OpenShift / HPC / AI workload management from the infra layer up; topic notes twice a week | All labs |
| [AI-infrastructure notes](notes/README.md) | Weekly notes from a 40-topic [curriculum](notes/CURRICULUM.md) | — |
| [NVIDIA AI infrastructure](NVIDIA/README.md) | NVIDIA foundations (NCA-AIIO prep) and GPU platform topics | — |

## How engineering notes relate to labs

**Theory note → lab runbook → run → evidence → status update**

A note explains a mechanism and makes claims; a lab tests those claims with controlled failures; evidence decides the status. A note never marks a lab as done.
