# Project AROHAN — Engineering Standards

Quality gates for every lab, note and script in Project AROHAN.

- **Principles** (how work is approached): [ENGINEERING_PRINCIPLES.md](ENGINEERING_PRINCIPLES.md)
- **Standards** (what a piece of work must meet): this file

---

## Status model

Status must reflect the actual repository state, not the intended one.

| Status | Icon | Meaning |
|---|---|---|
| Completed | ✅ | Implemented and validated, with evidence in the repo |
| Implemented | 🔵 | Implementation exists; validation or evidence still missing |
| In progress / ongoing | 🟢 | Active work, or a recurring series (e.g. weekly notes) |
| Planned | 🟡 | Designed (runbook or plan written), not yet run |
| Future | ⚪ | Part of the longer-term direction; no work started |

## Definition of Done

A capability is ✅ only when, where applicable:

| Area | Requirement |
|---|---|
| Problem | The engineering problem is clearly defined |
| Architecture | Design and dependencies are documented |
| Implementation | The implementation works |
| Observability | Health and operational signals are available |
| Validation | Expected behaviour is verified |
| Failure | A controlled failure scenario is tested |
| Recovery | Recovery is performed and verified |
| Evidence | Proof is captured in `evidence/` |
| Documentation | Findings and limitations are written up |
| Git | The work is committed as a reviewable change |

Each lab README states which criteria apply to it.

## Evidence standard

Evidence is stored with its lab:

```text
labs/<lab>/evidence/
├── screenshots
├── validation records
├── command outputs
└── investigation notes
```

Evidence must show the actual system state, be clearly named, trace back to the implementation, support the stated conclusion, and contain no secrets or personal data.

## Lab lifecycle and maturity

Lifecycle: **Problem → Architecture → Implementation → Observability → Validation → Failure injection → Recovery → Evidence → Documentation → Automation**

A capability does not need to reach every stage at once, but its current stage must be clear. Maturity levels:

| Level | Name | Meaning |
|---|---|---|
| 1 | Implement | The capability works |
| 2 | Observe | Meaningful operational signals exist |
| 3 | Validate | Expected behaviour is tested |
| 4 | Break | Controlled failures are introduced |
| 5 | Recover | Recovery is validated |
| 6 | Automate | Operational responses are automated |
| 7 | Optimize | Performance, efficiency and capacity are improved |
| 8 | Predict | Failures or capacity problems are anticipated |
| 9 | Autonomize | Parts of the operational loop run safely with minimal human input |

## Failure engineering

**Inject → Detect → Diagnose → Remediate → Verify recovery → Record evidence**

Failure experiments must be controlled, reversible, observable and documented.

## Automation standard

Automation follows **manual → documented → scripted → declarative → automated → verified**. Automation should be declarative, idempotent, observable, testable and reversible. Automated remediation is not production-ready until its verification step has been proven.

## Reproducibility standard

Every lab records environment, tool and image versions, dependencies, configuration, validation steps and expected results.

## Security standard

Least privilege, RBAC, network and workload isolation, and multi-tenancy are considered in every lab. Credentials, private keys, tokens and sensitive configuration are never committed to Git.

## Documentation standard

Significant work documents, where relevant: objective, problem, environment, architecture, implementation, observability, validation, failure testing, recovery, evidence, findings, limitations and next steps. It uses the status model above.

## Git standard

Changes are focused, traceable and reviewable; unrelated changes go in separate commits. Commit format:

```text
<type>(<scope>): <description>

feat(lab03): add gang deadlock manifest
fix(lab01): correct alert threshold
docs(standards): rewrite engineering principles
```

## Repository relationship

| Directory | Role |
|---|---|
| `engineering/` | Direction, architecture and deep-dive notes |
| `standards/` | Principles and quality gates (this folder) |
| `labs/` | Hands-on implementations, experiments and evidence |
