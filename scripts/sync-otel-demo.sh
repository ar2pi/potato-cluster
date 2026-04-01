#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$REPO_DIR"

git fetch origin main

if git diff --name-only HEAD origin/main | grep -q 'kubernetes/helm/otel-demo/values.yaml'; then
  git pull origin main
  helm upgrade --install --create-namespace -n otel-demo \
    -f kubernetes/helm/otel-demo/values.yaml \
    otel-demo open-telemetry/opentelemetry-demo
fi
