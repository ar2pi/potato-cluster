#!/bin/bash
set -euo pipefail

# Script to apply hello-api memory limit fix for issue #63
# This resolves config drift where the repository has the correct 384Mi limit
# but the running cluster still has 128Mi causing OOMKills

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELLO_API_DIR="kubernetes/resources/hello-api"

echo "=========================================="
echo "hello-api OOMKill Fix - Issue #63"
echo "=========================================="
echo ""
echo "Problem: Running pods have 128Mi limit causing OOMKills"
echo "Solution: Apply existing 384Mi limit from repository"
echo ""

# Verify we're in a git repository and on the right path
if [ ! -d "$REPO_DIR/$HELLO_API_DIR" ]; then
  echo "Error: Cannot find hello-api deployment directory"
  echo "Expected: $REPO_DIR/$HELLO_API_DIR"
  exit 1
fi

cd "$REPO_DIR"

# Check current deployment state
echo "Checking current deployment state in cluster..."
echo ""
CURRENT_LIMIT=$(kubectl get deployment hello-api -n hello-api -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null || echo "NOT FOUND")
echo "Current memory limit in cluster: $CURRENT_LIMIT"

# Show what's in the repository
REPO_LIMIT=$(grep -A 2 "limits:" "$REPO_DIR/$HELLO_API_DIR/hello-api-deployment.yaml" | grep memory | awk '{print $2}' | tr -d '"' | head -1)
echo "Memory limit in repository:     $REPO_LIMIT"
echo ""

if [ "$CURRENT_LIMIT" = "$REPO_LIMIT" ]; then
  echo "✓ Cluster already matches repository configuration!"
  echo "  No changes needed."
  exit 0
fi

echo "Config drift detected! Applying fix..."
echo ""

# Apply the deployment using kubectl replace --force
# This ensures immediate application even if there are conflicts
echo "Applying hello-api-deployment.yaml..."
kubectl replace --force -f "$REPO_DIR/$HELLO_API_DIR/hello-api-deployment.yaml" || {
  echo "Replace failed, trying apply instead..."
  kubectl apply -f "$REPO_DIR/$HELLO_API_DIR/hello-api-deployment.yaml"
}

echo ""
echo "Waiting for rollout to complete..."
kubectl rollout status deployment/hello-api -n hello-api --timeout=120s

echo ""
echo "=========================================="
echo "✓ Fix Applied Successfully!"
echo "=========================================="
echo ""

# Verify the new limit
NEW_LIMIT=$(kubectl get deployment hello-api -n hello-api -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}')
echo "New memory limit in cluster: $NEW_LIMIT"
echo ""

# Check pod status
echo "Current pod status:"
kubectl get pods -n hello-api -l app=hello-api
echo ""

echo "Expected outcomes:"
echo "  • Memory limit increased from 128Mi to 384Mi"
echo "  • OOMKills should stop (peak usage ~128MB vs 384Mi limit = ~33% usage)"
echo "  • Pods will have 3x more memory headroom"
echo ""
echo "Monitor pods with: kubectl get pods -n hello-api -w"
echo "Check restart counts: kubectl get pods -n hello-api -o wide"
echo ""
