# Module 02 – AI Infrastructure

> NVIDIA AI Infrastructure Engineering Journey
>
> PROJECT AROHAN (आरोहण)

---

# Overview

This module covers the core AI infrastructure technologies required for the NVIDIA Certified Associate – AI Infrastructure & Operations (NCA-AIIO) certification.

The focus is on understanding how NVIDIA GPUs, networking, storage, and interconnect technologies work together to enable modern AI workloads.

---

# Learning Objectives

After completing this module, I should be able to:

- Explain GPU Architecture
- Understand CUDA
- Explain Tensor Cores
- Understand GPU Memory Hierarchy
- Differentiate PCIe and NVLink
- Explain NVSwitch
- Understand DGX and HGX platforms
- Explain InfiniBand
- Understand RDMA
- Explain RoCE
- Understand GPUDirect technologies

---

# Official Topics

---

## 1. GPU Architecture

GPU is a massively parallel processor designed to accelerate AI, Deep Learning, HPC, and scientific computing workloads.

Key Points

- Thousands of processing cores
- Parallel execution
- Optimized for matrix operations
- Accelerates AI training and inference

---

## 2. CUDA

CUDA (Compute Unified Device Architecture) is NVIDIA's parallel computing platform and programming model.

Purpose

- Enables software to use NVIDIA GPUs
- Accelerates AI applications
- Used by TensorFlow and PyTorch

Remember

GPU = Hardware

CUDA = Software

---

## 3. Tensor Cores

Tensor Cores are specialized hardware units inside NVIDIA GPUs.

Purpose

- Accelerate matrix multiplication
- Accelerate Deep Learning
- Improve AI Training
- Improve AI Inference

Remember

CUDA launches work.

Tensor Cores accelerate AI computation.

---

## 4. GPU Memory Hierarchy

GPU memory enables high-speed AI computation.

Important Components

- Cache
- VRAM
- GDDR
- HBM (High Bandwidth Memory)

HBM is optimized for AI and HPC workloads.

---

## 5. PCIe

PCIe (Peripheral Component Interconnect Express)

Purpose

- Connect CPU and GPU
- Transfer data between CPU memory and GPU memory

Remember

PCIe = CPU ↔ GPU

---

## 6. NVLink

NVLink is NVIDIA's high-speed GPU interconnect.

Purpose

- GPU-to-GPU communication
- Multi-GPU AI training
- Faster communication than relying only on CPU-mediated communication

Remember

NVLink = GPU ↔ GPU

---

## 7. NVSwitch

NVSwitch enables efficient communication among many GPUs.

Purpose

- Multi-GPU AI servers
- Large AI workloads
- High scalability

Remember

NVSwitch connects multiple GPUs together.

---

## 8. DGX and HGX

### DGX

Complete NVIDIA AI system.

### HGX

NVIDIA AI server platform used by OEM partners.

Remember

DGX = Complete AI System

HGX = AI Server Platform

---

## 9. InfiniBand

InfiniBand is a high-speed, low-latency networking technology.

Used for

- AI clusters
- HPC
- Distributed AI training
- Supercomputers

Remember

InfiniBand connects AI servers.

---

## 10. RDMA

Remote Direct Memory Access

Purpose

- Direct memory communication
- Reduced CPU overhead
- Lower latency
- Higher throughput

Remember

RDMA = Direct Memory Access

---

## 11. RoCE

RDMA over Converged Ethernet.

Purpose

- Provides RDMA capabilities over Ethernet
- Supports distributed AI workloads on Ethernet infrastructure

Remember

RoCE = RDMA + Ethernet

---

## 12. GPUDirect

GPUDirect improves efficient data movement involving GPU memory.

Includes

- GPUDirect
- GPUDirect RDMA
- GPUDirect Storage

Purpose

- Reduce unnecessary data copies
- Lower latency
- Improve GPU utilization

Remember

CUDA = Compute

GPUDirect = Data Movement

---

# NVIDIA AI Infrastructure Flow

```text
AI Application
        │
        ▼
AI Framework
(PyTorch / TensorFlow)
        │
        ▼
CUDA
        │
        ▼
GPU
├── CUDA Cores
├── Tensor Cores
└── HBM
        │
        ▼
PCIe / NVLink / NVSwitch
        │
        ▼
InfiniBand / RoCE
        │
        ▼
GPUDirect
        │
        ▼
Distributed AI Infrastructure
```

---

# Key Comparisons

| Technology | Purpose |
|------------|---------|
| CUDA | GPU Computing Platform |
| Tensor Cores | AI Matrix Operations |
| HBM | High-Bandwidth GPU Memory |
| PCIe | CPU ↔ GPU |
| NVLink | GPU ↔ GPU |
| NVSwitch | Multiple GPUs |
| InfiniBand | Server ↔ Server |
| RDMA | Direct Memory Access |
| RoCE | RDMA over Ethernet |
| GPUDirect | Efficient GPU Data Movement |

---

# Module Summary

This module introduced the major NVIDIA AI Infrastructure technologies used to build modern AI platforms.

The concepts covered include GPU computing, memory hierarchy, interconnects, networking, distributed AI infrastructure, and efficient data movement.

Understanding these technologies provides the foundation required for NVIDIA AI Operations and enterprise AI infrastructure.

---

PROJECT AROHAN (आरोहण)

**Ascending to Greater Heights**

**One Step Higher. Every Day. 🚀**
