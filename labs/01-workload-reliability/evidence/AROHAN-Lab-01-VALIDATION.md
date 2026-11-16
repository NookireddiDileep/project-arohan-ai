# AROHAN Lab 01 — GPU Workload Reliability

## Objective

Establish the first AROHAN workload-reliability control loop:

**Observe → Measure → Detect → Alert → Inject Failure → Validate → Recover**

The lab uses a baseline NGINX workload to establish the reliability pattern that will later be extended to GPU and AI workloads.

## Environment

| Component | Value |
|---|---|
| Cloud | GCP |
| Kubernetes | K3s |
| Node | `platform-engineer-lab` |
| Workload Namespace | `default` |
| Observability Namespace | `arohan-observability` |
| Workload | `arohan-baseline` |
| Container | `nginx` |
| Memory Limit | `128Mi` |
| Prometheus Helm Chart | `prometheus-community/prometheus` |
| Chart Version | `29.23.0` |
| Prometheus Version | `3.13.2` |
| kube-state-metrics | Enabled |
| Prometheus Persistence | `10Gi` |
| StorageClass | `local-path` |
| Retention | `7d` |

## Architecture

```text
Kubernetes / K3s
      |
      +--> arohan-baseline / NGINX
      |          |
      |          +--> cAdvisor container telemetry
      |
      +--> kube-state-metrics
                 |
                 +--> Kubernetes resource limits
                              |
                              v
                         Prometheus
                              |
                              v
                 Memory Utilization SLI
                              |
                              v
                >80% for 2 minutes
                              |
                              v
                       Alert lifecycle
                    INACTIVE → PENDING
                              → FIRING
                              → INACTIVE
```

## Observability Foundation

Prometheus was deployed with persistent storage and workload resource limits:

```yaml
server:
  persistentVolume:
    enabled: true
    accessModes:
      - ReadWriteOnce
    size: 10Gi
    storageClass: local-path

  retention: 7d

  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

kube-state-metrics:
  enabled: true
```

Alertmanager, node-exporter and pushgateway were disabled for this lab.

## Baseline Workload

The baseline workload was verified as running:

```text
arohan-baseline-77977b8bb6-jpjfw
```

The NGINX container had a configured memory limit of:

```text
128Mi
```

## Metrics Validation

Container CPU telemetry was validated with:

```promql
rate(
  container_cpu_usage_seconds_total{
    container="nginx",
    pod=~"arohan-baseline.*"
  }[5m]
)
```

Container memory telemetry was validated with:

```promql
container_memory_working_set_bytes{
  container="nginx",
  pod=~"arohan-baseline.*"
}
```

The Kubernetes memory limit was obtained through kube-state-metrics:

```promql
kube_pod_container_resource_limits{
  namespace="default",
  container="nginx",
  pod=~"arohan-baseline.*",
  resource="memory"
}
```

The baseline limit was verified as:

```text
134217728 bytes = 128Mi
```

## Important Troubleshooting Finding

The resource-limit metric was initially unavailable because kube-state-metrics was disabled.

After enabling:

```yaml
kube-state-metrics:
  enabled: true
```

and upgrading Prometheus, the resource-limit metric became available.

This demonstrated an important observability dependency: workload reliability signals may require correlation between runtime telemetry, Kubernetes metadata and declared resource configuration.

## Reliability SLI

The first AROHAN workload-reliability signal was defined as:

```text
Memory Utilization %
=
Working Set Memory
------------------ × 100
Memory Limit
```

PromQL:

```promql
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
```

The `on(namespace,pod,container)` clause correlates the runtime container metric with the corresponding Kubernetes resource-limit metric.

## Reliability Alert

Alert:

```text
ArohanBaselineHighMemoryUtilization
```

Configuration:

```yaml
for: 2m

labels:
  severity: warning
  component: workload
  category: resource
```

The two-minute duration makes the alert represent sustained resource pressure rather than a transient spike.

## Rule Validation

The live rule was validated with:

```bash
kubectl exec -n arohan-observability   arohan-prometheus-server-99ff488f7-jrs2n   -c prometheus-server --   promtool check rules /etc/config/arohan-reliability.rules.yaml
```

Result:

```text
Checking /etc/config/arohan-reliability.rules.yaml
  SUCCESS: 1 rules found
```

The rule was also confirmed through the running Prometheus rules API with:

```text
name: ArohanBaselineHighMemoryUtilization
health: ok
interval: 30
```

## Controlled Failure Injection

A temporary workload was created:

```text
arohan-baseline-memory-test
```

with:

```text
memory limit: 128Mi
```

and approximately:

```text
110Mi
```

of deliberate memory pressure.

Prometheus observed:

```text
115896320 bytes
```

against:

```text
134217728 bytes
```

Therefore:

```text
115896320 / 134217728 × 100
≈ 86.35%
```

This exceeded the 80% threshold.

## Alert Lifecycle

The actual experiment demonstrated:

```text
INACTIVE
   |
   | memory pressure injected
   v
PENDING
   |
   | sustained >80% for 2 minutes
   v
FIRING
   |
   | test workload removed
   v
INACTIVE
```

Observed firing value:

```text
86.35%
```

Observed state:

```text
firing
```

Health:

```text
ok
```

After deleting the test workload:

```text
state: inactive
alerts: []
health: ok
```

> The original failure-injection terminal session was lost after the GCP SSH disconnect. The PENDING/FIRING/RECOVERY values above are documented from the actual Prometheus API output captured during the original experiment. They are not represented as newly captured screenshots.

## Evidence Captured

Current-state screenshots captured after SSH recovery:

1. **Prometheus Health**
   - `Prometheus Server is Healthy.`
   - `Prometheus Server is Ready.`

2. **Reliability Rule**
   - `ArohanBaselineHighMemoryUtilization`
   - `state: inactive`
   - `health: ok`
   - `interval: 30`

3. **promtool Validation**
   - `SUCCESS: 1 rules found`

Recommended repository layout:

```text
evidence/
├── 01-prometheus-health.png
├── 02-reliability-rule.png
├── 03-promtool-validation.png
└── VALIDATION.md
```

## Git Checkpoints

Relevant implementation commits:

```text
544693d  feat(arohan): add workload reliability alert rule
7c0796d  feat(arohan): configure workload reliability rule
1fe1746  feat(arohan): load workload reliability rules
```

The repository was verified clean after implementation:

```text
nothing to commit, working tree clean
```

## Engineering Capabilities Demonstrated

- Kubernetes workload observability
- Prometheus deployment and Helm configuration
- kube-state-metrics integration
- cAdvisor/container telemetry
- PromQL
- Metric correlation using `on(...)`
- Resource-utilization SLI design
- Sustained-condition alerting
- Controlled failure injection
- Alert lifecycle validation
- Recovery validation
- Prometheus rule validation with `promtool`
- Git-based infrastructure change management
- Troubleshooting missing observability dependencies

## Portfolio Outcome

The lab establishes the first AROHAN reliability control loop:

```text
Telemetry
   ↓
Metric Correlation
   ↓
Reliability SLI
   ↓
Threshold + Duration
   ↓
Prometheus Alert
   ↓
Failure Detection
   ↓
Recovery Detection
```

This is the foundation for:

```text
SLI
 ↓
SLO
 ↓
Error Budget
 ↓
Burn Rate
 ↓
Automated Remediation
 ↓
GPU Workload Reliability
 ↓
AI Inference Reliability
 ↓
Autonomous AI Infrastructure Operations
```

## Recruiter Summary

> Built and validated a Kubernetes workload-reliability control loop using Prometheus and kube-state-metrics, including live metric correlation, sustained memory-pressure detection, controlled failure injection, alert lifecycle validation and recovery verification.

## Status

**LAB 01 — COMPLETE ✅**

- Implementation: Complete
- Validation: Complete
- Failure injection: Complete
- Recovery validation: Complete
- Git checkpoint: Clean
- Recruiter evidence: Captured
