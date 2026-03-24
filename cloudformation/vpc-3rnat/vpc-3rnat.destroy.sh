#!/usr/bin/env bash
set -euo pipefail

TENANT_ID="${TENANT_ID:-main}"
ENV_ID="${ENV_ID:-main}"

delete_if_exists() {
  local stack_name="$1"

  if aws cloudformation describe-stacks --stack-name "$stack_name" >/dev/null 2>&1; then
    echo "==> Deleting $stack_name..."
    aws cloudformation delete-stack --stack-name "$stack_name"
    aws cloudformation wait stack-delete-complete --stack-name "$stack_name"
    echo "    Deleted $stack_name"
  else
    echo "==> Stack not found: $stack_name"
  fi
}

# Reverse dependency order: NAT -> private subnets -> VPC
delete_if_exists "${TENANT_ID}-${ENV_ID}-vpc-3rnat-02-nat"
delete_if_exists "${TENANT_ID}-${ENV_ID}-vpc-3rnat-01-private"
delete_if_exists "${TENANT_ID}-${ENV_ID}-vpc-3rnat-00-vpc"

echo "==> Done."
