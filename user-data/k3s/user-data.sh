#!/usr/bin/env bash
set -e

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

echo "[$(date -Iseconds)] Setting up k3s on Amazon Linux 2023 [1357]"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
<<<<<<< HEAD
ARTIFACTS_BUCKET=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$(ec2-metadata --instance-id | cut -d ' ' -f 2)" "Name=key,Values=artifacts-bucket" --query 'Tags[0].Value' --output text)
=======
DEFAULT_ARTIFACTS_BUCKET="gitops-artifacts-${ACCOUNT_ID}"

IMDS_TOKEN=$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)
INSTANCE_ID=$(curl -sS -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" \
  "http://169.254.169.254/latest/meta-data/instance-id" || true)
REGION=$(curl -sS -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" \
  "http://169.254.169.254/latest/meta-data/placement/region" || true)

if [[ -n "${INSTANCE_ID}" && -n "${REGION}" ]]; then
  TAGGED_BUCKET=$(aws ec2 describe-tags \
    --region "${REGION}" \
    --filters "Name=resource-id,Values=${INSTANCE_ID}" "Name=key,Values=ARTIFACTS_BUCKET" \
    --query "Tags[0].Value" --output text 2>/dev/null || true)
else
  TAGGED_BUCKET=""
fi

if [[ -n "${TAGGED_BUCKET}" && "${TAGGED_BUCKET}" != "None" ]]; then
  ARTIFACTS_BUCKET="${TAGGED_BUCKET}"
  echo "Using ARTIFACTS_BUCKET from instance tag: ${ARTIFACTS_BUCKET}"
else
  ARTIFACTS_BUCKET="${DEFAULT_ARTIFACTS_BUCKET}"
  echo "Using default ARTIFACTS_BUCKET: ${ARTIFACTS_BUCKET}"
fi
>>>>>>> 752c53a (chore: workspace sync 2026-03-27)
LOG_FILE="/var/log/cloud-init-output.log"

# echo "Installing base dependencies"
# retry 5 10 dnf install -y curl tar gzip jq ca-certificates
#update-ca-trust

export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
export PATH="$PATH:/usr/local/bin"

echo "Installing k3s"
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644 --disable traefik" sh -

echo "Waiting for Kubernetes API"
retry 30 5 kubectl get nodes

echo "Waiting for node to be Ready"
kubectl wait --for=condition=Ready node --all --timeout=300s

echo "[$(date -Iseconds)] k3s setup complete"

echo "Uploading artifacts to S3 [$ARTIFACTS_BUCKET]"
if aws s3api head-bucket --bucket "${ARTIFACTS_BUCKET}" 2>/dev/null; then
  aws s3 cp "${LOG_FILE}" "s3://${ARTIFACTS_BUCKET}/k3s/cloud-init-output.log"
  aws s3 cp "${KUBECONFIG}"  "s3://${ARTIFACTS_BUCKET}/k3s/kubeconfig.yaml"
  echo "[$(date -Iseconds)] Artifacts uploaded to s3://${ARTIFACTS_BUCKET}/k3s/"
else
  echo "[$(date -Iseconds)] ERROR: Bucket '${ARTIFACTS_BUCKET}' does not exist or is not accessible. Artifacts not uploaded."
fi

