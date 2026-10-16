#!/usr/bin/env bash
# Wait until Argo CD reports every Application as Synced and Healthy.
# Usage: hack/wait-for-apps.sh [timeout-seconds] [minimum-app-count]
set -euo pipefail

timeout="${1:-900}"
min_apps="${2:-1}"
deadline=$((SECONDS + timeout))

while true; do
  rows="$(kubectl get applications.argoproj.io -n argocd \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.sync.status}{"\t"}{.status.health.status}{"\n"}{end}' 2>/dev/null || true)"
  total="$(grep -c . <<<"$rows" || true)"
  ready="$(awk -F'\t' '$2 == "Synced" && $3 == "Healthy"' <<<"$rows" | grep -c . || true)"

  echo "--- $(date +%T)  ${ready}/${total} ready (need at least ${min_apps})"
  column -t -s $'\t' <<<"$rows" || true

  if (( total >= min_apps && ready == total )); then
    echo "All applications are Synced and Healthy."
    exit 0
  fi
  if (( SECONDS >= deadline )); then
    echo "Timed out after ${timeout}s." >&2
    exit 1
  fi
  sleep 15
done
