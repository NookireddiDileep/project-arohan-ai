# AROHAN Lab 01 — Workload Reliability Foundation

> **Project AROHAN — Autonomous AI Infrastructure & Operations**

## Status

**LAB 01 — COMPLETE ✅**

| Capability | Status |
|---|---|
| Kubernetes workload baseline | ✅ |
| Prometheus observability | ✅ |
| kube-state-metrics | ✅ |
| Container CPU / memory telemetry | ✅ |
| Resource-limit correlation | ✅ |
| Reliability SLI | ✅ |
| Reliability alert | ✅ |
| Controlled failure injection | ✅ |
| Alert lifecycle validation | ✅ |
| Recovery validation | ✅ |
| promtool validation | ✅ |
| Evidence captured | ✅ |
| Git documentation | ✅ |

---

## 🎯 Objective

Establish the first AROHAN workload-reliability control loop:

**Observe → Measure → Detect → Alert → Inject Failure → Validate → Recover**

The lab establishes a reusable reliability pattern that will later evolve toward GPU and AI workloads.

```text
Kubernetes Workload Reliability
        ↓
GPU Workload Reliability
        ↓
AI Inference Reliability
        ↓
Predictive Operations
        ↓
Autonomous AI Infrastructure

The current lab uses a baseline NGINX workload to establish the reliability pattern before applying the same engineering principles to GPU and AI workloads.

## 🧩 Engineering Problem

A Kubernetes workload having a configured memory limit does not by itself tell us whether the workload is operating safely.

AROHAN needs to answer:

How much memory is the workload actually using?
What is its configured memory limit?
Is utilization approaching the limit?
Is the condition transient or sustained?
Can the platform detect the condition automatically?
Does the alert actually fire against live telemetry?
Does the alert recover when the condition disappears?

Lab 01 implements and validates this control loop.

## 🏗️ Environment
Component	Value
Cloud	GCP
Kubernetes	K3s
Node	platform-engineer-lab
Workload Namespace	default
Observability Namespace	arohan-observability
Baseline Workload	arohan-baseline
Container	nginx
Memory Limit	128Mi
Prometheus Helm Chart	prometheus-community/prometheus
Chart Version	29.23.0
Prometheus Version	3.13.2
kube-state-metrics	Enabled
Prometheus Persistence	10Gi
StorageClass	local-path
Prometheus Retention	7d
## 🔭 Architecture
                         AROHAN LAB 01
                              |
                              v
                    +--------------------+
                    |   Kubernetes/K3s   |
                    |                    |
                    | arohan-baseline    |
                    |      NGINX         |
                    +---------+----------+
                              |
                              | container telemetry
                              v
                    +--------------------+
                    | cAdvisor / kubelet |
                    +---------+----------+
                              |
                              v
                    +--------------------+
                    |    Prometheus      |
                    |                    |
                    | CPU / Memory       |
                    | workload metrics   |
                    +---------+----------+
                              ^
                              |
                    +---------+----------+
                    | kube-state-metrics |
                    |                    |
                    | Resource limits    |
                    +--------------------+
                              |
                              v
                   Memory Utilization SLI
                              |
                              v
                    > 80% for 2 minutes
                              |
                              v
                  ArohanBaselineHighMemory
                              |
                              v
                    PENDING → FIRING
                              |
                              v
                         Recovery
                              |
                              v
                         INACTIVE
## 📁 Repository Structure
labs/01-gpu-workload-reliability/
├── README.md
├── workload/
├── observability/
│   ├── README.md
│   ├── prometheus-values.yaml
│   └── arohan-reliability.rules.yaml
└── evidence/
    ├── 01 AROHAN LAB 01 — PROMETHEUS HEALTH.PNG
    ├── 02 AROHAN LAB 01 — RELIABILITY RULE.PNG
    ├── 03 AROHAN LAB 01 PROMTOOL VALIDATION.PNG
    └── AROHAN-Lab-01-VALIDATION.md
## 📊 Observability Foundation

Prometheus was deployed using Helm with persistent storage:

server:
  persistentVolume:
    enabled: true
    accessModes:
      - ReadWriteOnce
    size: 10Gi
    storageClass: local-path

  retention: 7d

Prometheus resources:

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

kube-state-metrics was enabled:

kube-state-metrics:
  enabled: true

Alertmanager, node-exporter and pushgateway were intentionally disabled for this lab.

## 🧪 Baseline Workload

The baseline workload was verified as:

arohan-baseline-77977b8bb6-jpjfw

Status:

READY   STATUS
1/1     Running

The NGINX container memory limit was verified as:

128Mi

This workload acts as the initial reliability target.

## 📈 Metrics Validation
### CPU Telemetry

Container CPU telemetry was validated with:

rate(
  container_cpu_usage_seconds_total{
    container="nginx",
    pod=~"arohan-baseline.*"
  }[5m]
)
### Memory Telemetry

Container memory usage was validated with:

container_memory_working_set_bytes{
  container="nginx",
  pod=~"arohan-baseline.*"
}
### Kubernetes Memory Limit

The configured memory limit was obtained from kube-state-metrics:

kube_pod_container_resource_limits{
  namespace="default",
  container="nginx",
  pod=~"arohan-baseline.*",
  resource="memory"
}

The configured limit was:

134217728 bytes = 128Mi
## 🔧 Important Troubleshooting Finding

The resource-limit metric was initially unavailable.

Investigation identified that kube-state-metrics was disabled.

The configuration was changed to:

kube-state-metrics:
  enabled: true

After the Helm upgrade, the resource-limit metric became available.

### Engineering Lesson

A useful workload-reliability signal can require correlation between:

Runtime telemetry
       +
Kubernetes metadata
       +
Declared resource configuration

This was an actual observability dependency discovered and resolved during the lab.

## 📐 Reliability SLI

The first AROHAN workload-reliability SLI measures memory utilization against the configured memory limit.

Memory Utilization %
=
Working Set Memory
------------------ × 100
Memory Limit

PromQL:

(
  100 * container_memory_working_set_bytes{
    namespace="default",
    container="nginx",
    pod=~"arohan-baseline.*"
  }
  / on(namespace,pod,container)
  kube_pod_container_resource_limits{
    namespace="default",
    container="nginx",
    pod=~"arohan-baseline.*",
    resource="memory"
  }
) > 80

The important correlation mechanism is:

on(namespace,pod,container)

This matches runtime container telemetry with the corresponding Kubernetes resource-limit metric.

## 🚨 Reliability Alert

Alert name:

ArohanBaselineHighMemoryUtilization

Threshold:

> 80%

Sustained duration:

2 minutes

Labels:

severity: warning
component: workload
category: resource

The two-minute duration prevents a short-lived memory spike from immediately becoming a reliability event.

## ⚙️ Prometheus Rule Integration

The reliability rule was loaded into Prometheus through:

/etc/config/arohan-reliability.rules.yaml

Prometheus configuration was verified to contain:

rule_files:
  - /etc/config/recording_rules.yml
  - /etc/config/alerting_rules.yml
  - /etc/config/rules
  - /etc/config/alerts
  - /etc/config/arohan-reliability.rules.yaml

The live rule was confirmed through the Prometheus rules API.

## ✅ Rule Validation

The rule was validated using Prometheus promtool:

kubectl exec -n arohan-observability \
  arohan-prometheus-server-99ff488f7-jrs2n \
  -c prometheus-server -- \
  promtool check rules /etc/config/arohan-reliability.rules.yaml

Result:

Checking /etc/config/arohan-reliability.rules.yaml
  SUCCESS: 1 rules found
## 💥 Controlled Failure Injection

A temporary workload was created:

arohan-baseline-memory-test

Configured memory limit:

128Mi

The workload was deliberately configured to generate approximately:

110Mi

of memory pressure.

Prometheus observed:

115896320 bytes

against:

134217728 bytes

Therefore:

115896320 / 134217728 × 100
≈ 86.35%

This exceeded the reliability threshold of 80%.

## 🔄 Alert Lifecycle

The actual experiment demonstrated:

              Normal
                |
                v
             INACTIVE
                |
        Memory pressure
          injected
                |
                v
             PENDING
                |
       >80% sustained
          for 2 min
                |
                v
             FIRING
                |
       Test workload
           removed
                |
                v
             INACTIVE

Observed firing value:

86.35%

Observed state:

firing

Health:

ok
## ♻️ Recovery Validation

The injected test workload was deleted:

kubectl delete pod arohan-baseline-memory-test

Prometheus subsequently returned:

state: inactive
alerts: []
health: ok

This validated both failure detection and recovery detection.

## 📸 Evidence

Recruiter-facing evidence is stored under:

evidence/
01 — Prometheus Health

01 AROHAN LAB 01 — PROMETHEUS HEALTH.PNG

Demonstrates:

Prometheus Server is Healthy.
Prometheus Server is Ready.
02 — Reliability Rule

02 AROHAN LAB 01 — RELIABILITY RULE.PNG

Demonstrates the live Prometheus rule:

ArohanBaselineHighMemoryUtilization
state: inactive
health: ok
interval: 30
03 — promtool Validation

03 AROHAN LAB 01 PROMTOOL VALIDATION.PNG

Demonstrates:

SUCCESS: 1 rules found
### Detailed Validation Record

AROHAN-Lab-01-VALIDATION.md

Contains the implementation, validation, failure-injection and recovery record.

The original failure-injection terminal session was lost after a GCP SSH disconnect. The PENDING/FIRING/RECOVERY results documented in the validation record are based on the actual Prometheus API output captured during the original experiment.

## 🧠 What Was Proven
### Observe

Collect workload-level CPU and memory telemetry.

### Correlate

Join runtime metrics with Kubernetes resource metadata.

### Measure

Calculate memory utilization relative to the declared limit.

### Detect

Identify sustained resource pressure.

### Alert

Transition:

INACTIVE → PENDING → FIRING
### Recover

Detect the disappearance of the failure condition:

FIRING → INACTIVE
## 🛠️ Engineering Capabilities Demonstrated
Kubernetes workload observability
K3s platform operations
Prometheus deployment
Helm configuration
kube-state-metrics
cAdvisor telemetry
PromQL
Metric correlation with on(...)
Reliability SLI design
Threshold-based alerting
Sustained-condition alerting
Controlled failure injection
Alert lifecycle validation
Recovery validation
promtool validation
Git-based engineering workflow
Troubleshooting observability dependencies
## 🧾 Git Implementation

Relevant implementation checkpoints:

544693d  feat(arohan): add workload reliability alert rule
7c0796d  feat(arohan): configure workload reliability rule
1fe1746  feat(arohan): load workload reliability rules

Evidence checkpoint:

6b04bb9  docs(arohan): add lab 01 validation evidence

Repository verification:

nothing to commit, working tree clean
## 💼 Recruiter Summary

Built and validated a Kubernetes workload-reliability control loop using Prometheus and kube-state-metrics, correlating live container telemetry with Kubernetes resource limits, detecting sustained memory pressure, validating controlled failure injection and alert lifecycle transitions, and verifying recovery.

## 🎤 Interview Story

"For AROHAN Lab 01, I built a workload reliability control loop on K3s. I deployed Prometheus with kube-state-metrics, validated container telemetry, and correlated working-set memory with the Kubernetes memory limit using PromQL. I then created a sustained 80% memory-utilization alert. To prove the implementation worked against live telemetry, I injected controlled memory pressure, observed approximately 86.35% utilization, verified the alert transition from pending to firing, removed the test workload, and confirmed recovery back to inactive. I also validated the rule using promtool and preserved the implementation and evidence in Git."

## 🚀 Evolution Path

Lab 01 establishes the first reliability layer:

LAB 01
Workload Reliability
        |
        v
SLI
        |
        v
LAB 02
SLO + Error Budget
        |
        v
Burn Rate
        |
        v
Automated Remediation
        |
        v
GPU Workload Reliability
        |
        v
AI Inference Reliability
        |
        v
Predictive Operations
        |
        v
Autonomous AI Infrastructure
## 🏁 Final Status

AROHAN LAB 01 — WORKLOAD RELIABILITY FOUNDATION

Implementation       ✅ COMPLETE
Observability        ✅ COMPLETE
SLI                  ✅ COMPLETE
Alerting             ✅ COMPLETE
Failure Injection    ✅ COMPLETE
Alert Validation     ✅ COMPLETE
Recovery Validation  ✅ COMPLETE
Evidence              ✅ CAPTURED
Documentation        ✅ COMPLETE
Git Checkpoint       ✅ CLEAN

LAB 01 COMPLETE ✅
