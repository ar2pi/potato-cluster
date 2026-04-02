# KubeContainerOomKiller Runbook

## Alert: KubeContainerOOMKiller

**Severity:** Warning/Critical  
**Description:** Container has been OOMKilled (Out Of Memory killed) by the Kubernetes scheduler.

---

## Symptoms

- Pods showing high restart counts
- Containers terminated with reason `OOMKilled`
- Application becomes unstable or unavailable
- Memory usage at or near container limits (>95%)
- Alert fired from Prometheus/Grafana monitoring

---

## Quick Diagnosis

### 1. Identify OOMKilled Pods

```bash
# Check pod status and restart counts
kubectl get pods -n <namespace> -o wide

# Check for OOMKilled containers
kubectl get pods -n <namespace> -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.containerStatuses[*]}{.lastState.terminated.reason}{"\n"}{end}{end}' | grep OOMKilled

# Describe a specific pod to see termination reason
kubectl describe pod <pod-name> -n <namespace> | grep -A 10 "Last State"
```

### 2. Check Memory Usage

```bash
# View current memory usage
kubectl top pods -n <namespace>

# Check pod resource limits
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[*].resources.limits.memory}'

# View detailed metrics (if metrics-server is installed)
kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespaces/<namespace>/pods/<pod-name> | jq
```

### 3. Review Deployment Configuration

```bash
# Check deployment resource configuration
kubectl get deployment <deployment-name> -n <namespace> -o yaml | grep -A 10 resources
```

---

## Root Cause Analysis

Common causes of OOMKills:

1. **Insufficient Memory Limits**: Container limit too low for actual application needs
2. **Memory Leaks**: Application not releasing memory properly
3. **Traffic Spikes**: Increased load causing higher memory consumption
4. **Config Drift**: Deployment files in repository don't match cluster state
5. **Missing Resource Requests/Limits**: No limits defined, using node defaults

---

## Resolution Steps

### Option 1: Config Drift (Repository has fix, cluster doesn't)

**This is the case for issue #63 - hello-api**

1. **Verify repository configuration:**
   ```bash
   # Check what's in the repository
   grep -A 5 "resources:" kubernetes/resources/<app>/<deployment>.yaml
   ```

2. **Compare with cluster state:**
   ```bash
   kubectl get deployment <deployment-name> -n <namespace> -o yaml | grep -A 10 resources
   ```

3. **Apply the fix:**
   ```bash
   # Use the sync script if available
   ./scripts/sync-hello-api.sh
   
   # Or apply directly
   kubectl replace --force -f kubernetes/resources/<app>/<deployment>.yaml
   
   # Wait for rollout
   kubectl rollout status deployment/<deployment-name> -n <namespace>
   ```

### Option 2: Increase Memory Limits (No fix in repository)

1. **Determine appropriate memory limit:**
   - Check peak memory usage from monitoring
   - Add 30-50% headroom for safety
   - Example: Peak 128MB → Set limit to 256Mi-384Mi

2. **Update deployment file:**
   ```yaml
   resources:
     limits:
       memory: "384Mi"  # Increased from 128Mi
     requests:
       memory: "256Mi"  # Set to reasonable baseline
   ```

3. **Apply the change:**
   ```bash
   kubectl apply -f kubernetes/resources/<app>/<deployment>.yaml
   kubectl rollout status deployment/<deployment-name> -n <namespace>
   ```

### Option 3: Memory Leak Investigation

If increasing limits doesn't help or memory keeps growing:

1. **Monitor memory over time:**
   ```bash
   # Watch memory usage
   watch kubectl top pods -n <namespace>
   ```

2. **Analyze application logs:**
   ```bash
   kubectl logs <pod-name> -n <namespace> --previous | tail -100
   ```

3. **Check for known memory leak endpoints:**
   - Review application code for memory leaks
   - Check if certain endpoints cause memory growth
   - Example: `/fail?with_mem_leak=1` in hello-api

4. **Enable profiling:**
   - Use tools like pyroscope for Python apps
   - Use pprof for Go apps
   - Analyze heap dumps

---

## Verification

After applying fixes:

```bash
# Check new pod status
kubectl get pods -n <namespace> -l app=<app-name>

# Verify memory limits are applied
kubectl get deployment <deployment-name> -n <namespace> -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}'

# Monitor for OOMKills (should be zero)
kubectl get pods -n <namespace> -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}'

# Watch memory usage percentage
kubectl top pods -n <namespace>
```

---

## Prevention

### 1. Set Appropriate Resource Limits

Always define both requests and limits:

```yaml
resources:
  requests:
    memory: "256Mi"  # Baseline memory needed
    cpu: "250m"
  limits:
    memory: "512Mi"  # Maximum allowed (with headroom)
    cpu: "500m"
```

### 2. Monitor and Alert

- Set up Prometheus/Grafana alerts for high memory usage
- Alert when usage > 80% of limit
- Track restart counts and OOMKill events

### 3. Load Testing

- Test application under expected peak load
- Measure actual memory requirements
- Size limits based on real data

### 4. Regular Audits

- Review resource limits quarterly
- Check for config drift between repository and cluster
- Update limits as application evolves

### 5. Implement Auto-Sync

Consider implementing:
- GitOps with ArgoCD or Flux for automatic synchronization
- CI/CD pipelines that apply changes automatically
- Scheduled sync scripts (cron jobs)

---

## Example: hello-api Issue #63

**Problem:**
- Pods running with 128Mi limit
- Peak usage: 127.74MB (99.8% of limit)
- OOMKills causing 157-711 restarts per pod

**Solution:**
- Repository already had 384Mi limit configured
- Config drift: cluster not updated
- Applied fix using: `./scripts/apply-hello-api-fix.sh`

**Outcome:**
- Memory usage now ~33% of limit (127MB / 384Mi)
- 3x safety margin prevents OOMKills
- Pods stable with zero restarts

---

## Related Tools

- **Cluster Monitoring**: `k9s -n <namespace> -c pods`
- **Metrics**: `kubectl top pods`
- **Logs**: `kubectl logs <pod-name> -n <namespace> --previous`
- **Events**: `kubectl get events -n <namespace> --sort-by='.lastTimestamp'`

---

## Escalation

If OOMKills persist after increasing limits:

1. Check for memory leaks in application code
2. Review application dependencies for known issues
3. Consider horizontal scaling (more pods vs larger pods)
4. Investigate node memory pressure
5. Contact application development team for optimization

---

**Last Updated:** 2026-04-02  
**Related Issues:** #63
