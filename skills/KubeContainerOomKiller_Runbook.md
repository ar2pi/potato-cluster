Keywords: KubeContainerOomKiller, OOMKilled, OOM, out of memory, memory limit, container killed, container restart, kubernetes, memory resource, helm, values.yaml

---

## Summary

A container exceeded its configured memory limit and was terminated by the Linux kernel OOM killer. This runbook guides automated and manual remediation by identifying the affected workload, verifying current memory usage, updating the memory limit in the relevant Helm values or Kubernetes manifest, and merging a pull request to trigger a rolling restart. Auto-remediation is preferred; escalate only if config location is unknown or metrics are unavailable.

---

## Preconditions / Prerequisites

- Alert: `KubeContainerOomKiller` is firing with labels `namespace` and `container` (or `pod`) populated.
- Access: read access to Kubernetes metrics (Prometheus) and cluster logs (Loki).
- GitHub integration configured and MCP tools available (required for PR auto-merge).
- Helm chart or Kubernetes manifest for the affected workload is identifiable via the known config registry below or by searching the codebase.

---

## Step-by-Step Procedure

### 1. Identify the affected workload

Extract from alert labels:
- `namespace`
- `container` (and/or `pod`)

If alert labels are incomplete, query Loki:
```logql
{namespace=""} |= "OOMKilled"
```
or Prometheus:
```promql
kube_pod_container_status_last_terminated_reason{reason="OOMKilled", namespace=""}
```

### 2. Check recent memory usage

Query peak memory usage over the past 24 hours to determine a safe new limit:
```promql
max_over_time(
 container_memory_working_set_bytes{
 namespace="",
 container=""
 }[24h]
)
```
Note the peak value. New limit should be ≥ 1.5× peak (round up to nearest 128Mi).

### 3. Check current memory limit

```promql
kube_pod_container_resource_limits{
 namespace="",
 container="",
 resource="memory"
}
```

### 4. Locate the config file

**Known cases (start here):**

| Workload | Namespace | Config file |
|---|---|---|
| Kafka (otel-demo) | otel-demo | [kubernetes/helm/otel-demo/values.yaml](https://github.com/ar2pi/potato-cluster/blob/main/kubernetes/helm/otel-demo/values.yaml) |

**Unknown workload:** Search the repository for the container name:
- Search `ar2pi/potato-cluster` for `` in YAML files.
- Look for `resources.limits.memory` near the container name.

### 5. Determine the new memory limit

- Use the value from Step 2 (1.5× peak, rounded to 128Mi boundary).
- Hard cap for Kafka in otel-demo: **2048Mi**.
- For other containers: apply judgment — do not exceed node allocatable memory.

### 6. Open and merge a pull request

Change requirements:
- Do not make any changes other than in the helm `values.yaml` files. Do not edit any of the scripts or actual code.
- Always start changes on a new branch and open a PR.
- Do not push, under any circunstance, directly to the `main` branch

For **Kafka in otel-demo** (auto-remediate):
1. Edit `kubernetes/helm/otel-demo/values.yaml` — bump Kafka memory limit to at most `2048Mi`.
2. Open a PR against `main` in `ar2pi/potato-cluster`
3. **Merge immediately without waiting for review.**

For **other known workloads** (auto-remediate if config is found):
1. Edit the identified config file with the new limit from Step 5.
2. Open a PR with a descriptive title: `fix: increase memory limit for in (OOMKill remediation)`
3. Merge immediately without waiting for review.

For **unknown workloads** (manual):
- Escalate to the owning team with the findings from Steps 1–3 attached.

---

## Decision Points and Branching Guidance

```
Alert fires
 │
 ├─ Workload in known config registry?
 │ ├─ YES → edit file, open PR, auto-merge → done
 │ └─ NO → search codebase for container name
 │ ├─ Found → edit file, open PR, auto-merge → done
 │ └─ Not found → escalate to owning team
 │
 └─ Memory metrics available?
 ├─ YES → use 1.5× peak for new limit
 └─ NO → use 2× current limit as a safe default; note in PR description
```

---

## Validation / Verification

After the PR is merged and the rolling restart completes (typically 2–5 min):

1. **Pod is Running:**
```promql
kube_pod_status_phase{namespace="", phase="Running"}
```
Expected: pod shows `Running`.

2. **Alert resolves** within one evaluation cycle after pod stabilizes.

---

## Troubleshooting Notes and Common Pitfalls

- **OOMKill recurs after limit increase:** workload has a memory leak. Increase limit temporarily and open a separate issue for heap profiling (Pyroscope).
- **Metrics show no data for 24h:** container was recently deployed — use 2× current limit as a safe default and monitor closely.
- **PR merge fails (branch protection):** check if a required CI check must pass first; wait for it or trigger it manually.
- **Kafka specifically:** the JVM heap is controlled by `KAFKA_HEAP_OPTS` in addition to the container limit — ensure the env var is consistent with the new limit (heap should be ≤ 75% of limit).
- **Multiple containers OOMKilling simultaneously:** likely a node memory pressure event rather than a single container issue. Check node-level memory and consider cluster scaling before bumping individual limits.

---

## Rollback / Recovery

If the new limit causes scheduling issues (pod cannot be placed due to node capacity):

1. Revert the commit or open a follow-up PR restoring the previous value.
2. Merge immediately.
3. Alternatively, reduce the new limit to a value between old and new that fits node allocatable memory:
```promql
kube_node_status_allocatable{resource="memory"}
```

If the rolling restart causes a service disruption:
- Check pod events: `kube_pod_container_status_waiting_reason`
- If `CrashLoopBackOff` appears, the issue is not memory — inspect logs before adjusting further.

---

## Relevant Dashboards, Datasources & Alerts

| Resource | Link |
|---|---|
| Kubernetes Monitoring / Namespaces | [App](/a/grafana-k8s-app/navigation/namespace) |
| Kubernetes Monitoring / Workloads | [App](/a/grafana-k8s-app/navigation/workload) |
| Alert rule: KubeContainerOomKiller | [Alerting](/alerting/grafana/cfhtf43nqsl4wb/view) |
| Explore — container memory | [Explore](/explore) with `container_memory_working_set_bytes` |
| GitHub config repo | [ar2pi/potato-cluster](https://github.com/ar2pi/potato-cluster) |