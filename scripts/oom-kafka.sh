#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VALUES_FILE="kubernetes/helm/otel-demo/values.yaml"

echo "Resetting kafka memory limit to 896Mi (chaos test threshold)"

cd "$REPO_DIR"

sed -i'' -e 's/memory: [0-9]*Mi/memory: 896Mi/' "$VALUES_FILE"

if git diff --quiet "$VALUES_FILE"; then
  exit 0
fi

git add "$VALUES_FILE"
git commit -m "chaos: reset kafka memory limit to 1024Mi"
git push

helm upgrade --install --create-namespace -n otel-demo \
  -f "$VALUES_FILE" \
  otel-demo open-telemetry/opentelemetry-demo
