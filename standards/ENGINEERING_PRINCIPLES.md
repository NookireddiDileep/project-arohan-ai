# Engineering Principles

> **Build it. Break it. Measure it. Document it. Only then automate it.**

These are the rules every lab, note and script in PROJECT AROHAN AI follows. Each principle says what it means in practice, so a reader can check it against the repository.

This file is the single source of truth for principles. Quality gates (status model, Definition of Done, evidence and Git standards) live in the [Standards README](README.md).

---

## 1. Understand before you build

Know why a technology exists, what problem it solves, how it works inside, and where it stops working before deploying it. Start with the architecture, then the commands.

**In practice:** theory comes before the lab. Lab 03 starts from the [Kubernetes scheduling deep dive](../engineering/gpu-scheduling/KUBERNETES_SCHEDULING_DEEP_DIVE.md); every workload-management topic explains the infra-layer mechanism before the exercise.

## 2. Break it on purpose

A system is not understood until you have seen it fail. Every lab includes at least one controlled, reversible failure and documents how it shows up, how it is diagnosed, how it is fixed and how recovery is verified.

**In practice:** Lab 01 injects memory pressure and follows the alert from firing to resolved. Lab 03 creates GPU fragmentation and a gang deadlock on purpose before fixing them.

## 3. Evidence over claims

Nothing is marked done without proof from a real run: command output, metrics, alert state, screenshots or validation records, stored in the lab's `evidence/` folder.

**In practice:** Lab 01 is ✅ because its [validation record](../labs/01-gpu-workload-reliability/evidence/AROHAN-Lab-01-VALIDATION.md) and promtool output exist. Labs 02 and 03 stay 🟡 until they have been run.

## 4. Honest status, always

Status shows the real state of the repository, not the intended one. Published work that has not been validated says so. Environment limits are stated up front.

**In practice:** unrun runbooks carry an honesty note (Lab 03); topic notes mark exercises ⚪ not run; the root README states that labs use CPU-only K3s and simulated GPUs, not real GPU hardware.

## 5. Automate only what you understand

Automation comes after a task has been done by hand, understood and validated, never before. Automating something you cannot debug manually only makes failures faster.

**In practice:** the path is manual → documented → scripted → declarative → automated → verified. Automated remediation is not trusted until verification proves it worked.

## 6. Change safely

Before any change, know its blast radius and how to roll it back. Make one change at a time and confirm the result before the next.

**In practice:** labs run in dedicated namespaces on disposable `kind`/K3s clusters; Lab 03 ships a `reset.sh` so each experiment can be undone before the next.

## 7. Least privilege and isolation by default

Workloads, people and automation get only the access they need. Tenants are separated by namespace, quota, RBAC and network policy. Secrets, keys and tokens never go into Git.

**In practice:** workloads set resource limits (Lab 01) and namespaces carry quotas (Lab 02); future AI-assisted remediation will run with explicitly scoped permissions.

## 8. Reproducible or it didn't happen

Another engineer must be able to repeat a result. Pin tool and image versions, keep every manifest and script in Git, and record the environment next to every result.

**In practice:** lab READMEs list tool versions and cluster size; benchmark tables record node, image tag and model beside the numbers; CI lints Bash, YAML and Markdown links on every push.

## 9. Cost-aware by design

Use the cheapest environment that proves the point. Spend on hardware only when a result cannot be shown any other way.

**In practice:** scheduling behaviour is proven with fake GPUs on `kind`; observability and reliability labs run on a small CPU-only GCP K3s cluster.

## 10. AI-assisted, human-verified

AI tools may help draft notes, lab designs and scripts. That assistance is disclosed, and every result, number and piece of evidence comes from my own runs and is reviewed by me before it is merged.

**In practice:** generated drafts arrive as pull requests and are merged only after review; the root README states which parts are AI-assisted.

---

## How these principles are applied

- **Every lab:** principles 1–9 apply; the [Definition of Done](README.md#definition-of-done) is the gate.
- **Every note:** principles 1, 3, 4 and 10 apply; sources are cited.
- **When a principle and a deadline conflict:** keep the principle and reduce scope, then record what was left out.

Principles change when experience shows a better rule. Changes are made through a pull request with the reason in the description.
