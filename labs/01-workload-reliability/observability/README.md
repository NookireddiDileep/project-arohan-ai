# AROHAN V0.1 — Observability

## Objective

Establish the first observability capability for AROHAN V0.1.

The purpose of this layer is to collect and expose operational signals required for:

- Workload health
- Resource utilization
- Failure detection
- Diagnosis
- Alerting
- Future automated remediation

## Current Environment

- Kubernetes: K3s
- Cloud: GCP
- Nodes: 1
- CPU: 4 vCPU
- Memory: approximately 15 GiB
- Metrics Server: Enabled
- Prometheus: ✅ deployed with Helm ([values](prometheus-values.yaml)), with kube-state-metrics
- Alert rule: ✅ [arohan-reliability.rules.yaml](arohan-reliability.rules.yaml), promtool-validated
- Grafana: 🟡 planned

## Observability Model

AROHAN will progressively collect:

- Kubernetes metrics
- Pod CPU and memory
- Node CPU and memory
- Application health
- Kubernetes events
- Container logs
- Application metrics
- GPU metrics in future GPU environments

## Initial Signal Flow

Kubernetes Workload
→ Metrics
→ Prometheus
→ Alerting
→ Diagnosis
→ Remediation

## Metrics Server vs Prometheus

Metrics Server provides short-term resource utilization information used by Kubernetes commands such as:

- kubectl top node
- kubectl top pod

Prometheus will provide persistent time-series collection, querying, alerting, and correlation capabilities.

## Phase 1 — ✅ done in Lab 01

Established:

- Prometheus deployment
- Prometheus configuration
- AROHAN workload discovery
- Kubernetes metrics collection
- Basic Prometheus queries
- Evidence capture

## Phase 2 — 🟡 planned (alert rules already done in Lab 01)

- Grafana dashboards
- Kubernetes event correlation
- Application metrics
- Incident detection

## Phase 3 — ⚪ future

Autonomous capabilities:

- Automated diagnosis
- Deterministic remediation
- Event-driven remediation
- AI-assisted RCA
- Autonomous operations

## Success Criteria

Observability will be considered successful when:

- Prometheus is running
- AROHAN workload metrics are available
- Kubernetes metrics can be queried
- Resource utilization can be correlated with workload health
- Evidence can be captured reproducibly
- The telemetry can support future failure detection

## Design Principle

AROHAN treats observability as an operational control plane rather than only a dashboarding capability.

The objective is not simply to visualize infrastructure.

The objective is to provide reliable signals for:

Observe → Detect → Diagnose → Decide → Remediate → Verify

## Status

Phase 1 complete as part of [Lab 01](../README.md) (validated 2026-08-10). Success criteria above are met; see the [validation record](../evidence/AROHAN-Lab-01-VALIDATION.md).
