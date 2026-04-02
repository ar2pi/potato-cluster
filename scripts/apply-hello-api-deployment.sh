#!/bin/bash
set -e

echo "=========================================="
echo "Applying hello-api Deployment Configuration"
echo "=========================================="
echo ""
echo "Context: Fixing OOM kill issue from incident at 18:23:20Z"
echo "Issue #63 fix was closed but never applied to cluster"
echo "Current metrics show NO memory limits configured"
echo "Applying 384Mi memory limit (provides headroom over 132.6MB peak usage)"
echo ""

# Verify the deployment file exists
if [ ! -f "kubernetes/resources/hello-api/hello-api-deployment.yaml" ]; then
    echo "ERROR: Deployment file not found at kubernetes/resources/hello-api/hello-api-deployment.yaml"
    exit 1
fi

echo "✓ Deployment file found"
echo ""

# Show what we're about to apply
echo "Deployment configuration:"
echo "----------------------------------------"
cat kubernetes/resources/hello-api/hello-api-deployment.yaml
echo "----------------------------------------"
echo ""

# Apply the deployment
echo "Applying deployment to cluster..."
kubectl apply -f kubernetes/resources/hello-api/hello-api-deployment.yaml

echo ""
echo "Waiting for rollout to complete..."
kubectl rollout status deployment/hello-api -n default --timeout=5m

echo ""
echo "Verifying memory limits are configured..."
MEMORY_LIMIT=$(kubectl get deployment hello-api -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}')
echo "Memory limit configured: $MEMORY_LIMIT"

if [ "$MEMORY_LIMIT" != "384Mi" ]; then
    echo "WARNING: Expected 384Mi but got $MEMORY_LIMIT"
    exit 1
fi

echo ""
echo "Current pod status:"
kubectl get pods -l app=hello-api -o wide

echo ""
echo "=========================================="
echo "✅ SUCCESS: hello-api deployment applied"
echo "=========================================="
echo "Memory limits are now configured: 384Mi"
echo "This should prevent future OOM kills"
echo "Pods will be recreated with new limits"
