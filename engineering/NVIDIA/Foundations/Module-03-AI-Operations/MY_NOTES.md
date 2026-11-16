# Module 03 – AI Operations

> NVIDIA AI Infrastructure Engineering Journey
>
> PROJECT AROHAN AI (आरोहण)

---

# Overview

This module covers the operational technologies used to deploy, monitor, and manage NVIDIA AI infrastructure in production environments.

The focus is on Kubernetes orchestration, GPU lifecycle management, monitoring, inference services, and enterprise AI operations.

---

# Learning Objectives

After completing this module, I should be able to:

- Explain Kubernetes
- Understand GPU Operator
- Explain MIG
- Understand vGPU
- Monitor GPUs using nvidia-smi
- Understand DCGM
- Explain Triton Inference Server
- Understand NVIDIA NIM
- Explain Base Command Manager

---

# Official Topics

---

## 1. Kubernetes

Purpose

- Container orchestration
- Scheduling AI workloads
- Scaling applications
- Managing GPU-enabled containers

Remember

Kubernetes manages AI containers.

---

## 2. NVIDIA GPU Operator

Purpose

- Automates NVIDIA GPU software deployment
- Manages GPU drivers
- Manages CUDA components
- Manages Device Plugin
- Manages monitoring components

Remember

GPU Operator = Kubernetes automation for NVIDIA GPUs

---

## 3. Multi-Instance GPU (MIG)

Purpose

- Partition one supported GPU into multiple isolated GPU instances
- Improve GPU utilization
- Support multiple AI workloads

Remember

One GPU → Multiple GPU Instances

---

## 4. Virtual GPU (vGPU)

Purpose

- Share one physical GPU among multiple Virtual Machines
- Support virtualized GPU workloads

Remember

One GPU → Multiple Virtual Machines

---

## 5. NVIDIA System Management Interface (nvidia-smi)

Purpose

- Monitor GPU utilization
- View memory usage
- Check temperature
- Monitor GPU processes

Remember

Single GPU Monitoring

---

## 6. Data Center GPU Manager (DCGM)

Purpose

- Enterprise GPU monitoring
- GPU health monitoring
- Cluster-wide GPU management
- Diagnostics

Remember

Multi-GPU Monitoring

---

## 7. Triton Inference Server

Purpose

- Host trained AI models
- Serve inference requests
- Accelerate inference using NVIDIA GPUs

Remember

Training builds models.

Triton serves models.

---

## 8. NVIDIA Inference Microservices (NIM)

Purpose

- Ready-to-deploy AI inference services
- Simplified AI deployment
- GPU-optimized inference

Remember

NIM = Ready AI Service

---

## 9. Base Command Manager (BCM)

Purpose

- AI cluster management
- Cluster provisioning
- Monitoring
- Infrastructure operations

Remember

BCM = AI Cluster Management

---

# AI Operations Stack

```text
AI Application
        │
Container
        │
Kubernetes
        │
GPU Operator
        │
GPU Driver
        │
CUDA
        │
GPU
        ├── MIG
        ├── vGPU
        ├── nvidia-smi
        ├── DCGM
        └── BCM
        │
Triton
        │
NIM
        │
Inference
        │
Prediction
```

---

# Key Comparisons

| Technology | Purpose |
|------------|---------|
| Kubernetes | Container Orchestration |
| GPU Operator | GPU Software Management |
| MIG | GPU Partitioning |
| vGPU | GPU Virtualization |
| nvidia-smi | Single GPU Monitoring |
| DCGM | Enterprise GPU Monitoring |
| Triton | AI Model Serving |
| NIM | AI Inference Microservices |
| BCM | AI Cluster Management |

---

# Module Summary

This module introduced the operational technologies used to deploy, monitor, manage, and scale NVIDIA AI infrastructure.

The concepts covered include Kubernetes orchestration, GPU lifecycle management, virtualization, monitoring, inference services, and enterprise AI cluster operations.

Understanding these technologies completes the conceptual knowledge required for the NVIDIA Certified Associate – AI Infrastructure & Operations (NCA-AIIO) certification.

---

PROJECT AROHAN AI (आरोहण)

**Ascending to Greater Heights**

**One Step Higher. Every Day. 🚀**
