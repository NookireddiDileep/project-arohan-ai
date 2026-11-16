#!/usr/bin/env bash
# Exercise 7: install fake-gpu-operator + KAI Scheduler on the kai-lab kind cluster.
# Mirrors KAI's own kind e2e setup (hack/setup-e2e-cluster.sh @ v0.19.0), minus Prometheus/registry/DRA.
# Pinned versions: re-check KAI releases before bumping.
set -euo pipefail
KAI_VERSION="${KAI_VERSION:-v0.19.0}"
FGO_VERSION="${FGO_VERSION:-0.2.0}"
RAW="https://raw.githubusercontent.com/kai-scheduler/KAI-Scheduler/${KAI_VERSION}/hack"
WORK="$(mktemp -d)"

curl -fsSL "${RAW}/fake-gpu-operator-values.yaml"      -o "${WORK}/fgo-values.yaml"
curl -fsSL "${RAW}/kai-scheduler-fake-npe-values.yaml" -o "${WORK}/kai-npe-values.yaml"

echo "==> fake-gpu-operator ${FGO_VERSION} (8 fake Tesla-K80 per labelled node)"
helm upgrade -i gpu-operator oci://ghcr.io/run-ai/fake-gpu-operator/fake-gpu-operator \
  --namespace gpu-operator --create-namespace --version "${FGO_VERSION}" \
  --values "${WORK}/fgo-values.yaml" --set draPlugin.enabled=false --wait

echo "==> KAI Scheduler ${KAI_VERSION} (GPU sharing: NonMemoryEnforced)"
helm upgrade -i kai-scheduler oci://ghcr.io/kai-scheduler/kai-scheduler/kai-scheduler \
  -n kai-scheduler --create-namespace --version "${KAI_VERSION}" \
  --values "${WORK}/kai-npe-values.yaml" \
  --set global.gpuSharingMode=NonMemoryEnforced --wait

# Same RBAC KAI's e2e adds so the fake operator can update GPU-sharing reservation pods
kubectl create clusterrole pods-patcher --verb=patch --resource=pods --dry-run=client -o yaml | kubectl apply -f -
kubectl create rolebinding fake-status-updater --clusterrole=pods-patcher \
  --serviceaccount=gpu-operator:status-updater -n kai-resource-reservation --dry-run=client -o yaml | kubectl apply -f -

kubectl -n kai-scheduler get pods
kubectl get queues.scheduling.run.ai
kubectl get nodes -o custom-columns='NODE:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
