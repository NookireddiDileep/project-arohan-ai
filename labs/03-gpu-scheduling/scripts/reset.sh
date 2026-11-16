#!/usr/bin/env bash
# Clean slate between exercises: delete and recreate the lab namespace.
set -euo pipefail
NS="${1:-sched-lab}"
kubectl delete namespace "${NS}" --ignore-not-found --wait=true
kubectl create namespace "${NS}"
