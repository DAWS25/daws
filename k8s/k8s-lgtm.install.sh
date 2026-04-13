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

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

NS_EXISTS=$(kubectl get ns monitoring --ignore-not-found)
if [ -z "$NS_EXISTS" ]; then
    echo "Namespace 'monitoring' does not exist. Creating it."
    kubectl create namespace monitoring 
else
    echo "Namespace 'monitoring' already exists. Skipping creation."
fi

if command -v openssl >/dev/null 2>&1; then
    GRAFANA_ADMIN_PASSWORD="$(openssl rand -base64 24 | tr -d '\n' | tr '/+' 'AB' | cut -c1-24)"
else
    GRAFANA_ADMIN_PASSWORD="$(date +%s | sha256sum | cut -c1-24)"
fi

SECRETS_DIR="$DIR/../../.secrets/lgtm"
PASSWORD_FILE="$SECRETS_DIR/grafana-admin-password.txt"
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"
printf '%s\n' "$GRAFANA_ADMIN_PASSWORD" > "$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    --set grafana.service.type=LoadBalancer \
    --set-string grafana.adminPassword="$GRAFANA_ADMIN_PASSWORD"

####

kubectl --namespace monitoring get pods -l "release=prometheus"
kubectl --namespace monitoring get svc prometheus-grafana

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
