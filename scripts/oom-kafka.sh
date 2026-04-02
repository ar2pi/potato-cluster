#!/bin/bash
set -euo pipefail

# Kill switch for chaos engineering - disable by default after OOM remediation
if [[ "${CHAOS_ENABLED:-false}" != "true" ]]; then
  echo "Chaos testing disabled. Set CHAOS_ENABLED=true environment variable to re-enable."
  exit 0
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VALUES_FILE="kubernetes/helm/otel-demo/values.yaml"

echo "Resetting kafka memory limit to 512Mi"

cd "$REPO_DIR"

sed -i'' -e 's/memory: [0-9]*Mi/memory: 512Mi/' "$VALUES_FILE"

if git diff --quiet "$VALUES_FILE"; then
  exit 0
fi

git add "$VALUES_FILE"
git commit -m "chaos: reset kafka memory limit to 512Mi"
git push

helm upgrade --install --create-namespace -n otel-demo \
  -f "$VALUES_FILE" \
  otel-demo open-telemetry/opentelemetry-demo
