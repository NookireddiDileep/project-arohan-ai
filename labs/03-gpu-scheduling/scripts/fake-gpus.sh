#!/usr/bin/env bash
# Advertise fake GPUs on nodes labelled node-type=gpu and taint them like real GPU nodes.
# Uses the documented "advertise extended resources for a node" technique (PATCH node status).
# The scheduler treats nvidia.com/gpu exactly like a real device-plugin resource; nothing can USE a GPU, of course.
set -euo pipefail
GPUS_PER_NODE="${GPUS_PER_NODE:-4}"

for n in $(kubectl get nodes -l node-type=gpu -o name); do
  echo "==> ${n}: nvidia.com/gpu=${GPUS_PER_NODE} + taint nvidia.com/gpu=present:NoSchedule"
  kubectl patch "${n}" --subresource=status --type=json \
    -p "[{\"op\":\"add\",\"path\":\"/status/capacity/nvidia.com~1gpu\",\"value\":\"${GPUS_PER_NODE}\"}]"
  kubectl taint "${n}" nvidia.com/gpu=present:NoSchedule --overwrite
done

echo "Waiting for kubelet to reflect allocatable..."
sleep 10
kubectl get nodes -L node-type,gpu-model
kubectl get nodes -o custom-columns='NODE:.metadata.name,GPU_ALLOCATABLE:.status.allocatable.nvidia\.com/gpu,TAINTS:.spec.taints[*].key'
