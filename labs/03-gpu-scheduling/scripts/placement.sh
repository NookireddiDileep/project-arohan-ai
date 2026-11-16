#!/usr/bin/env bash
# Show where pods landed and how many GPUs each node has handed out.
# Usage: scripts/placement.sh [namespace]   (default: sched-lab)
set -euo pipefail
NS="${1:-sched-lab}"

echo "### Pods in ${NS}"
kubectl -n "${NS}" get pods -o custom-columns='POD:.metadata.name,PHASE:.status.phase,NODE:.spec.nodeName,SCHEDULER:.spec.schedulerName,GPU:.spec.containers[0].resources.limits.nvidia\.com/gpu' --sort-by=.spec.nodeName

echo
echo "### GPUs allocated per node (requests/limits from 'Allocated resources')"
for n in $(kubectl get nodes -o name); do
  line=$(kubectl describe "${n}" | awk '/Allocated resources/,/Events:/' | grep 'nvidia.com/gpu' || true)
  [ -n "${line}" ] && printf '%-32s %s\n' "${n#node/}" "${line}"
done

echo
echo "### Latest FailedScheduling reasons in ${NS}"
kubectl -n "${NS}" get events --field-selector reason=FailedScheduling \
  -o custom-columns='POD:.involvedObject.name,MESSAGE:.message' 2>/dev/null | tail -n 10 || true
