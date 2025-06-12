# potato-cluster

[ar2p2.grafana.net](https://ar2p2.grafana.net/) | [K8s metrics status](https://ar2p2.grafana.net/a/grafana-k8s-app/configuration/metrics-status)

Local experiments to feed telemetry into Grafana Cloud.

Prerequisites: [docker](https://www.docker.com), [kind](https://kind.sigs.k8s.io), [k9s](https://k9scli.io), [helm](https://helm.sh)

## Multi-node Kubernetes cluster

Launch a multi-node k8s cluster.

- Node 1: control-plane
- Node 2: worker
- Node 3: worker 2

```sh
kind create cluster --config kubernetes/config.yaml

# check the running nodes
k9s -c nodes

# install metrics server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch -n kube-system deployment metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

## Kubernetes monitoring

- [grafana/k8s-monitoring helm chart](https://github.com/grafana/k8s-monitoring-helm/blob/main/charts/k8s-monitoring/README.md)

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

# issue since v2.1 might need to rerun the install / delete alloy-* subcharts manually
# https://github.com/grafana/k8s-monitoring-helm/issues/1615

# check the running pods in the monitoring namespace
k9s -n monitoring -c pods

# check cadvisor metrics
kubectl proxy
curl http://localhost:8001/api/v1/nodes/potato-worker/proxy/metrics/cadvisor
```

## Resource stress test

Sample `stress-mem` and `stress-cpu` pods will hog resources to trigger generic Kubernetes alerting rules, available out of the box.  

```sh
kubectl replace --force -f kubernetes/manifests/noisy-neighborhood-pods.yaml

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
helm upgrade --install --create-namespace -n otel-demo-grafana-cloud -f kubernetes/helm/otel-demo/values.yaml otel-demo-grafana-cloud open-telemetry/opentelemetry-demo

# check the running deployments
# k9s -n otel-demo-local -c deploy
k9s -n otel-demo-grafana-cloud -c deploy

# port forward the frontend-proxy
# open http://localhost:8080
# open http://localhost:8080/grafana
```

## Python API with auto OTLP instrumentation

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
docker build -t ar2pi/hello-api --platform linux/amd64 hello-api
docker run -p 8000:8000 ar2pi/hello-api
docker push ar2pi/hello-api
```

### Deploy

```sh
kubectl replace --force -f kubernetes/manifests/hello-api-deployment.yaml -f kubernetes/manifests/hello-api-nginx-deployment.yaml

k9s -n hello-api -c pods

# port forward hello-api
kubectl port-forward -n hello-api svc/nginx-reverse-proxy 8000:8000
```

## Generate some traffic through k6

Prerequisites: [k6](https://grafana.com/docs/k6/latest/set-up/install-k6)

```sh
while true; do k6 run k6/loadtest.js; done

# to send metrics to grafana cloud via prom remote write:
while true; do
    K6_PROMETHEUS_RW_USERNAME="$K6_PROMETHEUS_RW_USERNAME" \
    K6_PROMETHEUS_RW_PASSWORD="$K6_PROMETHEUS_RW_PASSWORD" \
    K6_PROMETHEUS_RW_SERVER_URL="$K6_PROMETHEUS_RW_SERVER_URL" \
    k6 run -o experimental-prometheus-rw k6/loadtest.js
done

# monitor resource usage
k9s -n hello-api -c pods
```

- [k6 Prometheus dashboard](https://grafana.com/grafana/dashboards/19665-k6-prometheus/)

### NGINX exporter

- [https://github.com/nginx/nginx-prometheus-exporter]
- [https://github.com/nginx/nginx-prometheus-exporter/blob/main/grafana/README.md]

## Clean up

```sh
kubectl delete --ignore-not-found -f kubernetes/manifests/hello-api-deployment.yaml -f kubernetes/manifests/noisy-neighborhood-pods.yaml
helm uninstall -n otel-demo --ignore-not-found otel-demo
helm uninstall -n monitoring --ignore-not-found grafana-k8s-monitoring
helm uninstall -n monitoring --ignore-not-found grafana-k8s-monitoring-alloy-logs grafana-k8s-monitoring-alloy-metrics grafana-k8s-monitoring-alloy-profiles grafana-k8s-monitoring-alloy-receiver grafana-k8s-monitoring-alloy-singleton
kind delete cluster --name observons
```

## Additional resources

- [https://play.grafana.org/]
- [https://grafana.com/grafana/dashboards/]
