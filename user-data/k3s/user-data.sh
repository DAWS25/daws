#!/usr/bin/env bash
set -euo pipefail

# Retry helper: retry <max_attempts> <sleep_seconds> <command...>
retry() {
  local attempts="$1" delay="$2"; shift 2
  local i=1
  until "$@"; do
    if (( i >= attempts )); then
      echo "[$(date -Iseconds)] Command failed after $attempts attempts: $*"
      return 1
    fi
    echo "[$(date -Iseconds)] Attempt $i/$attempts failed, retrying in ${delay}s..."
    sleep "$delay"
    (( i++ ))
  done
}

echo "[$(date -Iseconds)] Starting k3s on Amazon Linux 2023"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ARTIFACTS_BUCKET="gitops-artifacts-${ACCOUNT_ID}"
LOG_FILE="/var/log/cloud-init-output.log"

echo "Installing base dependencies"
retry 5 10 dnf install -y curl tar gzip jq ca-certificates
update-ca-trust

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export PATH="$PATH:/usr/local/bin"

echo "Installing k3s"
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644 --disable traefik" sh -

echo "Waiting for Kubernetes API"
retry 30 5 kubectl get nodes

echo "Waiting for node to be Ready"
kubectl wait --for=condition=Ready node --all --timeout=300s

echo "[$(date -Iseconds)] k3s setup complete"

echo "Uploading artifacts to S3"
if aws s3api head-bucket --bucket "${ARTIFACTS_BUCKET}" 2>/dev/null; then
  aws s3 cp "${LOG_FILE}" "s3://${ARTIFACTS_BUCKET}/k3s/cloud-init-output.log"
  aws s3 cp "${KUBECONFIG}"  "s3://${ARTIFACTS_BUCKET}/k3s/kubeconfig.yaml"
  echo "[$(date -Iseconds)] Artifacts uploaded to s3://${ARTIFACTS_BUCKET}/k3s/"
else
  echo "[$(date -Iseconds)] ERROR: Bucket '${ARTIFACTS_BUCKET}' does not exist or is not accessible. Artifacts not uploaded."
fi

