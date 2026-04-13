#!/usr/bin/env bash
set -euo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
##

## Verify that k8s is up and running
echo "Verifying that k8s is up and running"
kubectl cluster-info

## Install LGTM

### Install Prometheus using Helm chart
echo "Installing Prometheus using Helm chart"

KUBE_PROM_STACK_VERSION="83.4.0"
LOKI_CHART_VERSION="6.55.0"
PROMTAIL_CHART_VERSION="6.17.1"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

NS_EXISTS=$(kubectl get ns monitoring --ignore-not-found)
if [ -z "$NS_EXISTS" ]; then
    echo "Namespace 'monitoring' does not exist. Creating it."
    kubectl create namespace monitoring
else
    echo "Namespace 'monitoring' already exists. Skipping creation."
fi

SECRETS_DIR="$DIR/../../.secrets/lgtm"
PASSWORD_FILE="$SECRETS_DIR/grafana-admin-password.txt"
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

if [ -f "$PASSWORD_FILE" ]; then
    GRAFANA_ADMIN_PASSWORD="$(tr -d '\r\n' < "$PASSWORD_FILE")"
elif command -v openssl >/dev/null 2>&1; then
    GRAFANA_ADMIN_PASSWORD="$(openssl rand -base64 24 | tr -d '\n' | tr '/+' 'AB' | cut -c1-24)"
else
    GRAFANA_ADMIN_PASSWORD="$(date +%s | sha256sum | cut -c1-24)"
fi

printf '%s\n' "$GRAFANA_ADMIN_PASSWORD" > "$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --version "$KUBE_PROM_STACK_VERSION" \
    --namespace monitoring \
    --create-namespace \
    --set grafana.service.type=LoadBalancer \
    --set-string grafana.adminPassword="$GRAFANA_ADMIN_PASSWORD"

echo "Installing Loki using Helm chart"

if helm status loki -n monitoring >/dev/null 2>&1; then
    CURRENT_LOKI_STATUS=$(helm status loki -n monitoring | awk -F': ' '/^STATUS:/{print $2}')
    CURRENT_LOKI_CHART=$(helm list -n monitoring | awk '$1=="loki" {print $6}')
    if [[ "$CURRENT_LOKI_STATUS" == "failed" || "$CURRENT_LOKI_CHART" == loki-stack-* ]]; then
        echo "Migrating legacy/failed Loki release ($CURRENT_LOKI_CHART, $CURRENT_LOKI_STATUS)"
        helm uninstall loki -n monitoring || true
    fi
fi

helm upgrade --install loki grafana/loki \
    --version "$LOKI_CHART_VERSION" \
    --namespace monitoring \
    --set deploymentMode=SingleBinary \
    --set singleBinary.replicas=1 \
    --set chunksCache.enabled=false \
    --set resultsCache.enabled=false \
    --set read.replicas=0 \
    --set write.replicas=0 \
    --set backend.replicas=0 \
    --set loki.auth_enabled=false \
    --set loki.commonConfig.replication_factor=1 \
    --set loki.storage.type=filesystem \
    --set loki.useTestSchema=true

echo "Installing Promtail using Helm chart"
helm upgrade --install promtail grafana/promtail \
    --version "$PROMTAIL_CHART_VERSION" \
    --namespace monitoring \
    --set-string config.clients[0].url=http://loki-gateway/loki/api/v1/push

kubectl --namespace monitoring delete daemonset loki-promtail --ignore-not-found

kubectl --namespace monitoring delete configmap grafana-loki-datasource --ignore-not-found

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-loki-datasource
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  loki-datasource.yaml: |
    apiVersion: 1
    datasources:
      - name: Loki
        type: loki
        access: proxy
        url: http://loki-gateway
        isDefault: false
        editable: true
EOF

echo "Restarting Grafana to load datasource changes"
kubectl --namespace monitoring rollout restart deployment/prometheus-grafana
kubectl --namespace monitoring rollout status deployment/prometheus-grafana --timeout=180s

####

kubectl --namespace monitoring get pods -l "release=prometheus"
kubectl --namespace monitoring get svc prometheus-grafana
kubectl --namespace monitoring get pods | grep -E 'loki|promtail' || true

echo "Waiting for Grafana external endpoint (LoadBalancer)..."
GRAFANA_HOST=""
for _ in {1..30}; do
    GRAFANA_HOST=$(kubectl --namespace monitoring get svc prometheus-grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [ -z "$GRAFANA_HOST" ]; then
        GRAFANA_HOST=$(kubectl --namespace monitoring get svc prometheus-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    fi
    if [ -n "$GRAFANA_HOST" ]; then
        break
    fi
    sleep 10
done

if [ -z "$GRAFANA_HOST" ]; then
    echo "Grafana external endpoint is not ready yet. Check later with: kubectl -n monitoring get svc prometheus-grafana"
else
    echo "Grafana URL: http://$GRAFANA_HOST"
fi

echo "Grafana user: admin"
echo "Grafana password: $GRAFANA_ADMIN_PASSWORD"
echo "Grafana password file: $PASSWORD_FILE"

####
##
popd
echo "script [$0] completed"
