# Monolith vs Microservices — the Operator's View

> **Project AROHAN AI · Engineering notes · Platform track (Stage 1)**
> The architecture debate is usually argued from the developer side. This note looks at what each shape costs to **run, patch, recover and troubleshoot**, and how a Kubernetes/OpenShift platform should support both.

> **The one-line answer:** start with a modular monolith; split along team, scaling, isolation or compliance boundaries when the cost of coordinating becomes higher than the cost of operating a distributed system — and measure that cost instead of following trends.

---

## 1. Running a monolith: what operations looks like

A well-run monolith is boring, and boring is a feature. The whole lifecycle fits in one head:

| Stage | Monolith in practice |
|---|---|
| Capacity | A few large servers or VMs; scale up first, then add identical nodes behind a load balancer |
| Patching | One OS/kernel baseline, one change window, one rollback plan |
| Releases | One artifact, one deployment, one version to reason about |
| HA / DR | Active-passive or a small cluster; DR drills test one dependency chain |
| Backup / restore | One application, one database, consistent restore points |
| Troubleshooting | One process tree, one log stream, `strace`/`perf` on one host |
| Migration | Lift-and-shift is realistic: move the VM, re-point storage and DNS |

**The catch is blast radius.** One bad release, one memory leak or one stuck NFS mount takes the whole application down. Scaling is all-or-nothing: you add capacity for everything to serve the busiest feature.

---

## 2. What changes when you split into microservices

Every function call that becomes a network call moves work from the code to the platform. Each hop adds:

| Cost | What it means operationally |
|---|---|
| Network plumbing | DNS lookups, conntrack entries, kube-proxy/OVN rules, often a sidecar proxy and an mTLS handshake |
| Resource overhead | Sidecars and agents on every pod, CPU limits that throttle them, more memory reserved per node |
| Failure modes | Timeouts, retries, retry storms, partial failures, version skew between services |
| Observability | Distributed tracing, per-service dashboards, SLOs and alerts, more on-call noise |
| Data consistency | One transaction becomes several: sagas, outbox pattern, idempotent consumers |
| Ownership | Every service needs an owner on call, a pipeline, a security baseline and patching |

### Tail latency compounds

If each of *n* internal calls on a request path is slow with probability *p*, the share of user requests that hit at least one slow call is:

```latex
P(\text{slow request}) = 1 - (1 - p)^{n}
```

With 15 calls at 1% each: 1 − 0.99¹⁵ ≈ **14% of user requests** are slow, while every service's average looks healthy. This is why fan-out architectures are judged on end-to-end p99, not per-service averages.

### Many "microservices problems" are kernel problems on the node

- conntrack table exhaustion → random connection failures ([Linux internals 07](../linux-internals/07-networking-and-firewall.md))
- CFS quota throttling of sidecars → latency at low CPU ([Linux internals 05](../linux-internals/05-cgroups-and-namespaces.md))
- DNS timeouts and ephemeral-port exhaustion under connection churn

Deeper troubleshooting path: [kernel troubleshooting roadmap](../kernel-troubleshooting/ROADMAP.md), Phases 3, 7 and 11.

---

## 3. Myths vs reality

| Popular claim | What actually happened |
|---|---|
| "Prime Video went back to a monolith" | One internal tool did: the audio/video quality-monitoring service, built on Step Functions and Lambda, was consolidated into one process and its infrastructure cost fell by over 90%. Prime Video as a whole did not. |
| "Shopify proves monoliths scale" | Shopify chose a *modular* monolith: one codebase and deployment with strictly enforced boundaries between components. The discipline is the point, not the single binary. |
| "Kubernetes means microservices" | Kubernetes/OpenShift run a monolith well: probes, self-healing, rolling deploys and autoscaling all still apply. |
| "Microservices = 500 ms and a $15k bill" | Infographic numbers, not measurements. The real costs are tail latency, operational toil and idle capacity spread across many small services. |

**Design lesson from Prime Video:** tightly coupled components that pass large volumes of data to each other belong in one process. That is a design rule, not an anti-microservices verdict.

---

## 4. When splitting is justified

| Reason | Example |
|---|---|
| Team boundaries | Many teams blocked on one release train and one shared test suite |
| Different scaling profiles | GPU model inference beside a CPU web tier: different hardware, cost and autoscaling signals ([AI inference on Kubernetes](../ai-inference/INFERENCE_ON_KUBERNETES.md)) |
| Fault isolation | A flaky export or reporting job must never take down checkout or login |
| Compliance boundaries | Payment or personal data in a separately audited, separately hardened component |
| Runtime / release cadence | A Python ML service beside a Java core; one changes daily, the other quarterly |

If none apply, splitting adds the costs in section 2 without the benefits.

---

## 5. The modular monolith done properly

A modular monolith only works with enforced boundaries:

- **Modules own their data:** separate schemas or tables per module; no cross-module joins.
- **Public interfaces only:** modules call each other through defined APIs, checked by tooling in CI (Shopify uses Packwerk for Rails).
- **One deployable, many owners:** code owners per module, one pipeline.
- **Ready to extract:** a module with clean boundaries can later become a service with little rework.

---

## 6. Migrating safely when you do split

1. **Measure first:** DORA metrics (deployment frequency, lead time, change failure rate, time to restore) and end-to-end p99. Split to fix a measured problem.
2. **Strangler fig pattern:** route one capability at a time to a new service behind the same entry point (Route/Ingress/API gateway); keep the monolith serving the rest.
3. **Extract the seam with the clearest reason** (table in section 4), not the easiest code.
4. **Platform readiness before traffic:** tracing, SLOs, alerts, an on-call owner, and node sizing for conntrack, DNS and sidecars.
5. **Verify and be willing to merge back** if the numbers don't improve.

---

## 7. Operator's checklist before splitting

1. Can each service be deployed, rolled back and patched independently, without a coordinated change window?
2. Are tracing, central logging and per-service SLOs in place *before* the split?
3. Is there an on-call owner for every service?
4. Is the platform sized for it: conntrack limits, DNS capacity, sidecar CPU/memory, pod IPs per node?
5. Do all internal calls have timeouts, retries with backoff and circuit breakers?
6. Can a DR drill still restore every data store to one consistent point in time?
7. Is end-to-end p99 measured, not just per-service averages?
8. Is the added cost (nodes, licences, observability, people) justified by a reason in section 4?

---

## 8. What this means for a platform team

The platform should not pick a side. A good Kubernetes/OpenShift platform runs a modular monolith (one Deployment, HPA, probes, PodDisruptionBudget) and a fleet of services (service mesh optional, not default) equally well — and makes the operating cost of each visible so teams decide with real numbers.

---

## Interview questions

1. **When would you advise against microservices?** Small team, one release cadence, tightly coupled data, no observability or on-call maturity.
2. **Why can a microservices app be slow when every service is fast?** Tail latency compounds across fan-out: 1 − (1 − p)ⁿ.
3. **What did Prime Video actually change?** One monitoring tool moved from Step Functions/Lambda to a single process; data passing through S3 between stages was the main cost.
4. **Does running on Kubernetes require microservices?** No. Kubernetes manages containers; a monolith still benefits from probes, rollouts and autoscaling.
5. **How would you migrate a monolith?** Measure, strangler fig behind the same entry point, extract the seam with a clear reason, platform readiness first, verify.

---

## Sources

- [Network World: 6 lessons from the Amazon Prime Video serverless vs. monolith flap](https://www.networkworld.com/article/972298/6-lessons-from-the-amazon-prime-video-serverless-vs-monolith-flap.html)
- [The New Stack: Prime Video's microservices move doesn't lead to a monolith after all](https://thenewstack.io/amazon-prime-videos-microservices-move-doesnt-lead-to-a-monolith-after-all/)
- [Shopify Engineering: Under deconstruction — the state of Shopify's monolith](https://shopify.engineering/shopify-monolith)
- [Shopify Engineering: Deconstructing the monolith](https://shopify.engineering/deconstructing-monolith-designing-software-maximizes-developer-productivity)
- [Martin Fowler: Strangler Fig Application](https://martinfowler.com/bliki/StranglerFigApplication.html) · [MonolithFirst](https://martinfowler.com/bliki/MonolithFirst.html)
- [DORA research program](https://dora.dev)
