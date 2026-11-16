# AI Infrastructure notes: daily curriculum

One note a day, in order. Each note: **concept in my own words → architecture → how it fails in operations → how to observe it (metrics, commands) → a small hands-on exercise (CPU-only K3s / kind / offline data) → interview questions → sources.**

Notes link back to the AROHAN labs where the topic is practised.

## Block A: GPU and node fundamentals
1. GPU architecture for operators: SMs, Tensor Cores, HBM, and why memory bandwidth matters for inference
2. NVLink, NVSwitch and PCIe topology: reading `nvidia-smi topo -m`
3. NVIDIA driver, CUDA, container toolkit and CDI: the version-compatibility chain
4. NVIDIA GPU Operator on Kubernetes/OpenShift: what each component does
5. GPU Feature Discovery and Node Feature Discovery: labels that drive scheduling
6. DCGM and dcgm-exporter: the GPU metrics that matter (util, memory, power, XID, ECC)
7. XID errors and GPU health: which ones mean "restart the app" vs "drain the node"
8. GPU sharing: time-slicing vs MPS vs MIG vs DRA, with isolation trade-offs
9. MIG profiles and planning on A100/H100

## Block B: Scheduling and multi-tenancy
10. kube-scheduler internals recap (links to the scheduling deep dive)
11. Topology Manager, CPU Manager and NUMA alignment for GPU pods
12. Kueue: queues, ClusterQueues, cohorts and admission
13. Volcano vs KAI vs Kueue: when to use which
14. Gang scheduling and the upstream Workload API
15. Priority, preemption and checkpoint-aware eviction
16. Quotas and fair-share for GPU teams (DRF)

## Block C: Training at scale
17. Distributed training patterns: data, tensor and pipeline parallelism (an ops view)
18. NCCL and collective communication: what all-reduce needs from the network
19. InfiniBand vs RoCE: RDMA, GPUDirect RDMA and GPUDirect Storage
20. Storage for AI: datasets, checkpoints, parallel filesystems vs object storage
21. Checkpointing strategy and failure rates at scale
22. Kubeflow Trainer / PyTorchJob / JobSet on Kubernetes

## Block D: Inference and serving
23. The inference request lifecycle: TTFT, TPOT, KV cache (links to the inference notes)
24. vLLM: PagedAttention and continuous batching (ops view)
25. NVIDIA Triton and NIM: what they add
26. KServe and OpenShift AI model serving
27. Autoscaling inference: queue depth vs GPU util vs latency signals
28. Model loading and cold starts: image size, weights, caching
29. Quantization and model size: the effect on GPU memory and cost

## Block E: Operations, SRE and FinOps
30. SLOs for AI services: what to measure and alert on
31. GPU observability stack on OpenShift: Prometheus, DCGM, Grafana
32. GPU FinOps: idle detection, cost per token, chargeback
33. Power, cooling and rack density in AI data centres (an ops view)
34. Incident patterns in GPU clusters: a field guide
35. Day-2 upgrades: drivers, operators and OpenShift with GPU nodes

## Block F: Architecture
36. Reference architecture: a 1,000-GPU training cluster
37. Reference architecture: a multi-tenant inference platform
38. Multi-cluster and hybrid GPU capacity
39. Security for AI platforms: isolation, supply chain, model and data access
40. Guarded autonomous operations: policy, verification and audit (the AROHAN direction)
