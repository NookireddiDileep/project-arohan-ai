# From GPU Cluster to GPU Cloud Service on OpenShift

> **Project AROHAN AI · Engineering notes · Platform track (Stage 1 → 2)**
> What a platform team actually has to build to deliver GPUs as a governed, self-service, metered service on OpenShift — and how the Red Hat + Rafay *Sovereign AI Cloud as a Service* reference architecture splits that work.

> **The one-line answer:** a GPU cluster gives you capacity; a GPU cloud service adds tenancy, a self-service catalogue, quota, metering, governance and day-2 operations on top. On OpenShift, most of the building blocks are operators — the hard part is designing how tenants consume them.

---

## 1. Cluster vs cloud service

Red Hat's framing of the reference architecture: *provisioning GPU compute as a cluster is not the same as delivering it as a cloud service* ([Red Hat blog](https://redhat.com/en/blog/rafay-and-red-hat-publish-joint-reference-architecture-sovereign-ai-cloud-service)).

| Question | GPU cluster | GPU cloud service |
|---|---|---|
| Who gets GPUs? | Whoever the admin gives access to | Any onboarded tenant, through a catalogue |
| How fast? | Tickets, days | Self-service, minutes |
| How much can they use? | Informal | Quota per tenant, borrowing rules, priorities |
| Who pays? | Shared budget | Usage metered per tenant, chargeback or billing |
| Isolation | Trust between teams | Enforced: compute, network, data, keys |
| Reliability | Best effort | SLOs, health loop, capacity planning |

The service layers sit **on top of** the orchestration layers described in [GPU cluster orchestration: the big picture](../gpu-scheduling/GPU_CLUSTER_ORCHESTRATION_OVERVIEW.md); the GPU-node specifics of OpenShift (Node Feature Discovery, GPU Operator, GPU MachineSets, non-root images) are in [OpenShift vs Kubernetes §8](OPENSHIFT_VS_KUBERNETES.md).

---

## 2. The service stack, layer by layer

| Layer | What it must do | OpenShift building blocks |
|---|---|---|
| Tenant / customer | Choose a service and size (SKU), get an isolated environment | Projects/namespaces, or a dedicated cluster per tenant |
| Self-service portal | Catalogue, provisioning, templates, onboarding | OpenShift AI dashboard and workbenches; console plug-ins; a commercial layer such as Rafay in the reference architecture |
| Governance, quota, metering | Policy, security, quotas, usage tracking, compliance | Red Hat build of Kueue, `ResourceQuota`/`LimitRange`, OpenShift AI hardware profiles, RBAC, SCCs, ACM policies, monitoring + DCGM metrics |
| AI platform | Run, scale and manage AI workloads | OpenShift + OpenShift AI (notebooks, pipelines, distributed training, model serving) |
| Fleet | Many clusters across sites and environments | Red Hat Advanced Cluster Management, hosted control planes |
| GPU infrastructure | GPUs, fabric, storage, nodes | NVIDIA GPU Operator, Network Operator, NFD, MachineSets, ODF or external storage |

---

## 3. Tenancy models: the first design decision

| Model | Isolation | Cost / density | Operations | Good for |
|---|---|---|---|---|
| **Namespace per tenant** on a shared cluster | Soft: RBAC, quotas, NetworkPolicy, SCCs; shared control plane and nodes | Highest density | One cluster to run | Internal teams in one organisation |
| **Dedicated node pools** per tenant (taints + labels) | Medium: no shared GPUs or nodes | Medium | Per-pool capacity planning | Teams with compliance needs |
| **Cluster per tenant** with hosted control planes | Strong: own API server and etcd; control planes run as pods on a management cluster | Lower density, cheaper than full clusters | ACM fleet management | External customers, regulated tenants |
| **VM or bare metal per tenant** (OpenShift Virtualization, GPU passthrough/vGPU) | Strongest | Lowest | Hardware lifecycle per tenant | Sovereign or "bring your own stack" customers |

Rule of thumb: internal platform → namespaces; selling to outside customers or strict sovereignty → cluster-per-tenant or VM/bare-metal.

---

## 4. The GPU catalogue (SKUs)

A service sells **sizes**, not "a GPU somewhere":

| SKU type | How it is built | Isolation | Typical use |
|---|---|---|---|
| Full GPU | Device plugin / DRA, whole device | Full | Training, large models |
| MIG slice (e.g. `1g.10gb`) | GPU Operator MIG manager, MIG strategy | Hardware: memory and compute partitioned | Inference, notebooks, small fine-tuning |
| Time-slice | Device plugin time-slicing config | None (shared memory, no fault isolation) | Dev/test, demos |
| Multi-GPU node / gang | Whole nodes, topology-aware placement | Full | Distributed training |

In OpenShift AI, users pick these through **hardware profiles**; for Kueue-managed workloads the profile must specify a local queue, and older accelerator profiles have to be migrated to hardware profiles ([OpenShift AI docs](https://docs.redhat.com/pt-br/documentation/red_hat_openshift_ai_self-managed/2.25/html/managing_openshift_ai/managing-workloads-with-kueue)).

---

## 5. Quota, fair sharing and metering

**Quota and queueing — Red Hat build of Kueue.** Released as an operator supported on OpenShift ([OpenShift docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/ai_workloads/red-hat-build-of-kueue)); it admits jobs against quota and order, injects node affinity through resource flavors and tracks each job as a `Workload`. Patterns:

- One `ClusterQueue` per tenant, grouped in a **cohort** so idle quota can be **borrowed** and reclaimed by **preemption**.
- `ResourceFlavor` per GPU type (e.g. H100 vs L40S vs MIG profile) so tenants are charged and placed correctly.
- **Count GPU memory, not devices:** with DRA, Kueue can charge quota by GPU memory, so a full 80 GB GPU and a 10 GB MIG slice no longer both count as "1" ([Red Hat Developer](https://developers.redhat.com/articles/2026/10/02/smarter-gpu-sharing-how-red-hat-build-of-kueue-works-with-dynamic-resource-allocation)).
- Red Hat has published a worked GPU-as-a-Service example combining Kueue, NVIDIA MIG and a small self-service dashboard plug-in ([Red Hat Developer](https://developers.redhat.com/articles/2026/06/29/implement-gpu-as-a-service-kueue)).

**Metering and chargeback.** Two different numbers matter:

| Metric | Source | Why |
|---|---|---|
| **Allocated** GPU-hours per tenant | Kueue workloads / pod requests over time | What the tenant reserved — usually what they pay for |
| **Used** GPU-hours / utilisation | DCGM exporter metrics (`DCGM_FI_DEV_GPU_UTIL`, framebuffer used) scraped by cluster monitoring | Whether reserved GPUs are actually working |

The gap between the two — **allocated but idle GPUs** — is the biggest cost leak in GPU platforms; alert on it (see [Lab 05 Ex 8](../../labs/05-gpu-cluster-operations/README.md)).

---

## 6. Governance and isolation

- **Identity and access:** SSO, per-tenant groups, RBAC; no cluster-admin for tenants.
- **Workload security:** `restricted-v2` SCC by default; only operator pods privileged; image policies and signed images.
- **Network:** NetworkPolicy / AdminNetworkPolicy per tenant; user-defined networks in OVN-Kubernetes for stronger separation; egress control.
- **Data:** per-tenant storage classes and encryption; keys held by the operator of the sovereign cloud, not the hardware vendor.
- **Fleet policy:** ACM policies to keep every tenant cluster compliant (versions, SCCs, quotas).
- **Audit:** API audit logs and usage records retained per tenant.

---

## 7. Sovereignty is more than location

| Dimension | Question to answer | Typical controls |
|---|---|---|
| Data sovereignty | Where do data, models and weights live? | In-country storage, residency policies |
| Operational sovereignty | Who can operate and access the platform? | Local operations staff, access controls, audit |
| Technical sovereignty | Can it run without outside dependencies? | Disconnected/air-gapped installs, mirrored registries (`oc-mirror`), open source stack |
| Legal / compliance | Which regulations apply? | Certifications, contractual controls, audit trails |

Red Hat positions OpenShift and OpenShift AI as the platform for sovereign and air-gapped "AI factories" ([Red Hat blog](https://www.redhat.com/en/blog/sovereign-ai-architecture-scaling-distributed-training-kubeflow-trainer-and-feast-red-hat-openshift-ai)); a separate sovereign AI-ready private cloud reference architecture combines Intel hardware-rooted trust, OpenShift and Deloitte's operational expertise ([Red Hat blog](https://www.redhat.com/en/blog/ai-tipping-point-why-sovereignty-no-longer-optional)).

---

## 8. Day-2 operations behind the service

A catalogue is only as good as the operations behind it:

- **Driver and operator lifecycle:** GPU Operator, driver and OpenShift upgrades planned together per node pool ([Lab 04 Ex 5](../../labs/04-gpu-infra-hands-on/README.md)).
- **Health loop:** DCGM health → alert → drain → requeue → repair → re-validate ([orchestration overview §3](../gpu-scheduling/GPU_CLUSTER_ORCHESTRATION_OVERVIEW.md)).
- **Capacity planning:** queue wait times, borrowing rates and utilisation per GPU flavor decide what to buy next.
- **Tenant onboarding/offboarding:** automated (GitOps), including quota, network, storage and metering setup.
- **SLOs per SKU:** e.g. time to provision an environment, queue wait at P95, GPU availability.

---

## 9. Where Red Hat + Rafay fit

In the joint reference architecture, Red Hat AI and OpenShift form the AI and multi-tenant cloud platform, and Rafay adds the **self-service commercial workflows** service providers need to resell that platform to their own customers ([Red Hat blog](https://redhat.com/en/blog/rafay-and-red-hat-publish-joint-reference-architecture-sovereign-ai-cloud-service)). Practically:

| Concern | Platform (OpenShift + OpenShift AI + operators) | Commercial / service layer (Rafay in this design) |
|---|---|---|
| Run GPU workloads, scheduling, isolation | ✅ | — |
| Quota, queues, GPU sharing | ✅ (Kueue, MIG, DRA) | Exposes them as products |
| Customer catalogue, SKU selection, onboarding | Partial (OpenShift AI dashboard) | ✅ |
| Billing, chargeback, customer-facing metering | Raw usage data | ✅ |

What the platform team still owns either way: tenancy design, GPU node and driver lifecycle, the health loop, capacity and SLOs.

---

## 10. Interview drill (30 seconds each)

1. **What's the difference between a GPU cluster and a GPU cloud service?** Tenancy, self-service catalogue, quota and fair sharing, metering/chargeback, governance and SLO-backed operations on top of the same hardware.
2. **Namespace-per-tenant or cluster-per-tenant?** Internal teams: namespaces with quotas and policies. External or regulated customers: hosted control planes per tenant, or VMs/bare metal for the strictest isolation.
3. **How do you stop one team from taking all the GPUs?** Kueue ClusterQueues per team in a cohort, borrowing with preemption, priorities; quota by GPU memory with DRA.
4. **How would you bill for GPUs?** Meter allocated GPU-hours per tenant and SKU from queue/pod data; show utilisation from DCGM; alert on idle allocations.
5. **What does "sovereign" mean for an AI platform?** Data, operational, technical and legal control in-country: residency, local operators, air-gapped capability, auditability.

---

## Practise it

- GPU sharing SKUs (time-slicing, MIG): [Lab 04 Ex 9](../../labs/04-gpu-infra-hands-on/README.md)
- Quota, borrowing and preemption with Kueue: [Lab 05 Ex 9](../../labs/05-gpu-cluster-operations/README.md)
- Metering signals and idle-GPU alerting: [Lab 05 Ex 8](../../labs/05-gpu-cluster-operations/README.md)

## Sources

- [Red Hat: Rafay and Red Hat publish joint reference architecture for Sovereign AI Cloud as a Service](https://redhat.com/en/blog/rafay-and-red-hat-publish-joint-reference-architecture-sovereign-ai-cloud-service)
- [OpenShift docs: Red Hat build of Kueue](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/ai_workloads/red-hat-build-of-kueue)
- [OpenShift AI docs: Managing workloads with Kueue](https://docs.redhat.com/pt-br/documentation/red_hat_openshift_ai_self-managed/2.25/html/managing_openshift_ai/managing-workloads-with-kueue)
- [Red Hat Developer: Implement GPU-as-a-Service with Kueue and NVIDIA MIG](https://developers.redhat.com/articles/2026/06/29/implement-gpu-as-a-service-kueue)
- [Red Hat Developer: Smarter GPU sharing — Red Hat build of Kueue with DRA](https://developers.redhat.com/articles/2026/10/02/smarter-gpu-sharing-how-red-hat-build-of-kueue-works-with-dynamic-resource-allocation)
- [Red Hat: Sovereign AI architecture with Kubeflow Trainer and Feast on OpenShift AI](https://www.redhat.com/en/blog/sovereign-ai-architecture-scaling-distributed-training-kubeflow-trainer-and-feast-red-hat-openshift-ai)
- [Red Hat: The AI tipping point — why sovereignty is no longer optional](https://www.redhat.com/en/blog/ai-tipping-point-why-sovereignty-no-longer-optional)
