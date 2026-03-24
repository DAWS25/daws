#!/usr/bin/env bash
set -euo pipefail

TENANT_ID="${TENANT_ID:-main}"
ENV_ID="${ENV_ID:-main}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Delete a stack if it's in ROLLBACK_COMPLETE (can't be updated, must be re-created)
ensure_deployable() {
  local stack_name="$1"
  local status
  status=$(aws cloudformation describe-stacks --stack-name "$stack_name" \
    --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "DOES_NOT_EXIST")
  if [[ "$status" == "ROLLBACK_COMPLETE" ]]; then
    echo "    Stack $stack_name is in ROLLBACK_COMPLETE — deleting before redeploy..."
    aws cloudformation delete-stack --stack-name "$stack_name"
    aws cloudformation wait stack-delete-complete --stack-name "$stack_name"
    echo "    Deleted."
  fi
}

echo "==> [1/3] Deploying VPC..."
ensure_deployable "${TENANT_ID}-${ENV_ID}-vpc-3rnat-00-vpc"
aws cloudformation deploy \
  --stack-name "${TENANT_ID}-${ENV_ID}-vpc-3rnat-00-vpc" \
  --template-file "$DIR/vpc-3rnat-00-vpc.cform.yaml" \
  --parameter-overrides TenantId="$TENANT_ID" EnvId="$ENV_ID"

echo "==> [2/3] Deploying Private Subnets..."
ensure_deployable "${TENANT_ID}-${ENV_ID}-vpc-3rnat-01-private"
aws cloudformation deploy \
  --stack-name "${TENANT_ID}-${ENV_ID}-vpc-3rnat-01-private" \
  --template-file "$DIR/vpc-3rnat-01-private.cform.yaml" \
  --parameter-overrides TenantId="$TENANT_ID" EnvId="$ENV_ID"

echo "==> [3/3] Deploying NAT Gateways..."
ensure_deployable "${TENANT_ID}-${ENV_ID}-vpc-3rnat-02-nat"
aws cloudformation deploy \
  --stack-name "${TENANT_ID}-${ENV_ID}-vpc-3rnat-02-nat" \
  --template-file "$DIR/vpc-3rnat-02-nat.cform.yaml" \
  --parameter-overrides TenantId="$TENANT_ID" EnvId="$ENV_ID"

echo "==> Done."
