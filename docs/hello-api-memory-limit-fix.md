# Hello-API Memory Limit Deployment Fix

## 🚨 Production Incident Response

This PR applies the hello-api deployment configuration with 384Mi memory limits to resolve an active production incident.

## Problem Summary

### What Happened
- **Incident Time**: 2026-04-02 at 18:23:20Z
- **Impact**: All 3 hello-api pods OOMKilled simultaneously
- **Result**: Service outage and SLO breach
- **Root Cause**: NO memory limits configured on pods despite Issue #63 being closed

### Timeline
1. **Issue #63**: Originally identified the need for memory limits
2. **Fix Merged**: Configuration created with 384Mi limit in `kubernetes/resources/hello-api/hello-api-deployment.yaml`
3. **Issue Closed**: Marked as resolved
4. **❌ PROBLEM**: Fix was NEVER actually applied to the cluster
5. **Today**: Metrics confirmed no memory limits configured, all pods OOMKilled

### Evidence
- Current metrics show **NO memory limits** on hello-api pods
- Memory usage peaked at **132.6 MB** before OOM kill
- 384Mi limit provides adequate headroom (2.9x peak usage)
- All 3 pods failed simultaneously indicating systemic issue

## Solution

This PR includes:

### 1. GitHub Actions Workflow (`.github/workflows/apply-hello-api-deployment.yaml`)
- Automatically applies deployment when merged to main
- Can also be triggered manually via workflow_dispatch
- Includes verification steps to confirm limits are applied

### 2. Manual Script (`scripts/apply-hello-api-deployment.sh`)
- For immediate application by ops team
- Includes safety checks and verification
- Can be run directly: `./scripts/apply-hello-api-deployment.sh`

### 3. Applies Existing Configuration
- Uses the already-reviewed 384Mi configuration from `kubernetes/resources/hello-api/hello-api-deployment.yaml`
- No new changes to the deployment spec itself
- Simply ensures the configuration is actually applied to the cluster

## Memory Configuration

```yaml
resources:
  limits:
    memory: 384Mi
  requests:
    memory: 256Mi
```

**Rationale**:
- Peak usage: 132.6 MB
- Limit: 384 MB (2.9x headroom)
- Request: 256 MB (1.9x typical usage)
- Provides safety margin while being resource-efficient

## Deployment Plan

### Immediate Actions (via script)
```bash
chmod +x scripts/apply-hello-api-deployment.sh
./scripts/apply-hello-api-deployment.sh
```

### Automated (via workflow)
- Workflow will trigger on merge to main
- Can also be manually triggered from Actions tab

### Verification
After deployment:
```bash
# Check memory limits are configured
kubectl get deployment hello-api -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}'

# Monitor pod status
kubectl get pods -l app=hello-api -o wide

# Check for OOM kills
kubectl get pods -l app=hello-api -o jsonpath='{.items[*].status.containerStatuses[*].lastState.terminated.reason}'
```

## Expected Outcome

✅ Memory limits configured on all hello-api pods  
✅ Pods can handle normal traffic without OOM kills  
✅ Cluster has proper resource boundaries  
✅ Future deployments will maintain these limits  

## Related Issues

- Closes #63 (properly this time - with actual cluster application)
- Fixes production incident at 18:23:20Z

## Urgency

**HIGH - Active Production Incident**

This PR should be merged immediately to:
1. Prevent continued service disruptions
2. Restore SLO compliance
3. Protect against cascading failures

---

## Post-Merge Actions

- [ ] Verify memory limits applied via kubectl
- [ ] Monitor pods for stability
- [ ] Update runbooks to include verification steps
- [ ] Review deployment process to ensure changes are applied to cluster
