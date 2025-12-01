# potato-cluster

[ar2p2.grafana.net](https://ar2p2.grafana.net/) | [K8s metrics status](https://ar2p2.grafana.net/a/grafana-k8s-app/configuration/metrics-status)

Local Kubernetes potato cluster and telemetry generator for Grafana Cloud demos.

Prerequisites: [docker](https://www.docker.com), [kind](https://kind.sigs.k8s.io), [k9s](https://k9scli.io), [helm](https://helm.sh)

## Multi-node Kubernetes cluster

Launch a multi-node k8s cluster.

- Node 1: control-plane
- Node 2: worker
- Node 3: worker 2

```sh
kind create cluster --config kubernetes/potato-cluster-config.yaml

# check cadvisor metrics (optional)
kubectl proxy
curl http://localhost:8001/api/v1/nodes/potato-worker/proxy/metrics/cadvisor

# install metrics server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch -n kube-system deployment metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# check the running nodes
k9s -c nodes
```

## Kubernetes monitoring

- [grafana/k8s-monitoring helm chart](https://github.com/grafana/k8s-monitoring-helm/blob/main/charts/k8s-monitoring/README.md)
- [Structure](https://github.com/grafana/k8s-monitoring-helm/blob/main/charts/k8s-monitoring/docs/Structure.md)

Grab [Grafana Kubernetes configuration](https://ar2p2.grafana.net/a/grafana-k8s-app/configuration), toggle desired features, copy paste and adjust `kubernetes/helm/grafana-k8s-monitoring/values.yaml` accordingly.

```sh
# alloy operator https://github.com/grafana/k8s-monitoring-helm/blob/main/charts/k8s-monitoring/README.md
kubectl apply -f https://github.com/grafana/alloy-operator/releases/latest/download/collectors.grafana.com_alloy.yaml

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

echo """
GRAFANA_METRICS_URL="REPLACE_ME"
GRAFANA_METRICS_USER="REPLACE_ME"
GRAFANA_CLUSTER_METRICS_URL="REPLACE_ME"
GRAFANA_LOGS_URL="REPLACE_ME"
GRAFANA_LOGS_USER="REPLACE_ME"
GRAFANA_OTLP_URL="REPLACE_ME"
GRAFANA_OTLP_USER="REPLACE_ME"
GRAFANA_PROFILES_URL="REPLACE_ME"
GRAFANA_PROFILES_USER="REPLACE_ME"
GRAFANA_ACCESS_TOKEN="REPLACE_ME"
""" > kubernetes/helm/grafana-k8s-monitoring/.env
export $(cat kubernetes/helm/grafana-k8s-monitoring/.env | xargs)

helm upgrade --install --atomic --timeout 300s -n monitoring --create-namespace grafana-k8s-monitoring grafana/k8s-monitoring \
  -f <(envsubst < kubernetes/helm/grafana-k8s-monitoring/values.yaml)

# issue since v2.1 might need to rerun the install to deploy missing alloy-* resources after an uninstall because of dangling operator finalizer
# https://github.com/grafana/k8s-monitoring-helm/issues/1615

# check the running pods in the monitoring namespace
k9s -n monitoring -c pods
```

## Resource stress test

Sample `stress-mem` and `stress-cpu` pods will hog resources to trigger generic Kubernetes alerting rules, available out of the box.  

```sh
kubectl create namespace noisy-neighborhood
kubectl replace --force -f kubernetes/resources/noisy-neighborhood

# monitor resource usage
k9s -n noisy-neighborhood -c pods
```

> NOTE: If containers last terminated reason is `Error` instead of `OOMKilled` and there are "failed to create inotify fd" warnings in the node logs then you probably need to [bump inotify resources](https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files) on the host

## Otel demo

- [OpenTelemetry Demo Docs](https://opentelemetry.io/docs/demo/)
- [Kubernetes deployment](https://opentelemetry.io/docs/demo/kubernetes-deployment/)

```sh
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts

# helm upgrade --install --create-namespace -n otel-demo-local -f kubernetes/helm/otel-demo/values-local.yaml otel-demo-local open-telemetry/opentelemetry-demo
helm upgrade --install --create-namespace -n otel-demo -f kubernetes/helm/otel-demo/values.yaml otel-demo open-telemetry/opentelemetry-demo

# check the running deployments
# k9s -n otel-demo-local -c deploy
k9s -n otel-demo -c deploy

# port forward the frontend-proxy
kubectl -n otel-demo port-forward svc/frontend-proxy 8080:8080

# open http://localhost:8080
# open http://localhost:8080/grafana
```

## Python API with OTLP instrumentation

- [Send data to the Grafana Cloud OTLP endpoint](https://grafana.com/docs/grafana-cloud/send-data/otlp/send-data-otlp/)

### Dev (optional)

Prerequisites: [python >=3.13.2](https://www.python.org/downloads/), [poetry](https://python-poetry.org/)

```sh
cd hello-api
poetry install
source .venv/bin/activate
uvicorn app:app --host 0.0.0.0 --port 8000
curl "http://localhost:8000/hello?name=world"
pip freeze > requirements.txt
```

### Build

```sh
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ar2pi/hello-api \
  --push .
```

### Deploy

```sh
kubectl create namespace hello-api
kubectl replace --force -f kubernetes/resources/hello-api

k9s -n hello-api -c pods

# port forward hello-api
kubectl port-forward -n hello-api svc/nginx-reverse-proxy 8000:8000
```

## Deploy standalone alloy for profiles

[Grafana Alloy Helm chart](https://github.com/grafana/alloy/tree/main/operations/helm/charts/alloy)

```sh
echo """
GRAFANA_PROFILES_URL="REPLACE_ME"
GRAFANA_PROFILES_USER="REPLACE_ME"
GRAFANA_ACCESS_TOKEN="REPLACE_ME"
""" > kubernetes/helm/alloy-sdk-profiles/.env
export $(cat kubernetes/helm/alloy-sdk-profiles/.env | xargs)

helm upgrade --install --create-namespace -n monitoring alloy-sdk-profiles grafana/alloy \
  -f <(envsubst < kubernetes/helm/alloy-sdk-profiles/values.yaml)
```

## Deploy standalone alloy for rabbitmq

[Grafana Alloy Helm chart](https://github.com/grafana/alloy/tree/main/operations/helm/charts/alloy)

```sh
echo """
GRAFANA_METRICS_URL="REPLACE_ME"
GRAFANA_METRICS_USER="REPLACE_ME"
GRAFANA_CLUSTER_METRICS_URL="REPLACE_ME"
GRAFANA_ACCESS_TOKEN="REPLACE_ME"
""" > kubernetes/helm/alloy-rabbitmq.env
export $(cat kubernetes/helm/alloy-rabbitmq/.env | xargs)

helm upgrade --install --create-namespace -n monitoring alloy-rabbitmq grafana/alloy \
  -f <(envsubst < kubernetes/helm/alloy-rabbitmq/values.yaml)
```

Run the rabbitmq pods
```sh
kubectl create namespace rabbitmq
kubectl replace --force -f kubernetes/resources/rabbitmq/
```

Install dashboards from https://ar2p2.grafana.net/connections/add-new-connection/rabbitmq

## Generate some traffic through k6

Prerequisites: [k6](https://grafana.com/docs/k6/latest/set-up/install-k6)

```sh
while true; do k6 run k6/loadtest.js; done

# to send k6 metrics to grafana cloud via prom remote write (optional):
export $(cat kubernetes/helm/grafana-k8s-monitoring/.env | xargs)
while true; do
    K6_PROMETHEUS_RW_USERNAME="$GRAFANA_METRICS_USER" \
    K6_PROMETHEUS_RW_PASSWORD="$GRAFANA_ACCESS_TOKEN" \
    K6_PROMETHEUS_RW_SERVER_URL="$GRAFANA_METRICS_URL" \
    k6 run -o experimental-prometheus-rw k6/loadtest.js
done

# monitor resource usage
k9s -n hello-api -c pods
```

- [k6 Prometheus dashboard](https://grafana.com/grafana/dashboards/19665-k6-prometheus/)

### NGINX exporter

- https://github.com/nginx/nginx-prometheus-exporter
- https://github.com/nginx/nginx-prometheus-exporter/blob/main/grafana/README.md

### Dasboards

@TODO: dashboards screenshots + json links
- fpog otel
- fpog beyla
- k6 results
- nginx exporter
- otel demo dashboard

## Clean up

```sh
kind delete cluster --name potato

# or more fine-grained
kubectl delete --ignore-not-found -f kubernetes/resources/noisy-neighborhood
kubectl delete --ignore-not-found -f kubernetes/resources/hello-api
kubectl delete --ignore-not-found -f kubernetes/resources/rabbitmq
helm uninstall -n otel-demo --ignore-not-found otel-demo
helm uninstall -n monitoring --ignore-not-found grafana-k8s-monitoring
helm uninstall -n monitoring --ignore-not-found alloy-sdk-profiles
# issue since v2.1 might need to remove alloy-* subcharts manually
# https://github.com/grafana/k8s-monitoring-helm/issues/1615
helm uninstall -n monitoring --ignore-not-found grafana-k8s-monitoring-alloy-logs grafana-k8s-monitoring-alloy-metrics grafana-k8s-monitoring-alloy-profiles grafana-k8s-monitoring-alloy-receiver grafana-k8s-monitoring-alloy-singleton
```

## Additional resources

- [play.grafana.org](https://play.grafana.org/)
- [grafana.com/grafana/dashboards](https://grafana.com/grafana/dashboards/)
- [Make your own potato battery](https://youtu.be/SOsE5ECH_IM?feature=shared)

## @TODO:

- [ ] install script, makefile all the things
- [ ] export Grafana dashboards
  - single pane of glass (otel)
  - single pane of glass (beyla)
  - warning and errors
  - otel-demo
  - nginx exporter
  - k6 metrics
