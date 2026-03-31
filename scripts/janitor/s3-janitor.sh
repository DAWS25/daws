#!/usr/bin/env bash
set -euo pipefail

echo -n ""

MAX_BUCKET_PASSES=50
MAX_BUCKET_RETRIES=8

current_region() {
  local region
  region="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
  if [[ -z "${region}" ]]; then
    region="$(aws configure get region 2>/dev/null || true)"
  fi
  if [[ -z "${region}" ]]; then
    echo "ERROR: AWS region is not configured. Set AWS_REGION, AWS_DEFAULT_REGION, or aws configure region." >&2
    exit 1
  fi
  echo "${region}"
}

bucket_region() {
  local bucket="$1"
  local loc
  loc=$(aws s3api get-bucket-location --bucket "${bucket}" --query 'LocationConstraint' --output text 2>/dev/null || echo "unknown")
  case "${loc}" in
    None|null|"") echo "us-east-1" ;;
    EU) echo "eu-west-1" ;;
    *) echo "${loc}" ;;
  esac
}

delete_bucket_configs() {
  local bucket="$1"
  aws s3api delete-bucket-policy --bucket "${bucket}" 2>/dev/null || true
  aws s3api delete-public-access-block --bucket "${bucket}" 2>/dev/null || true
  aws s3api delete-bucket-ownership-controls --bucket "${bucket}" 2>/dev/null || true
  aws s3api delete-bucket-website --bucket "${bucket}" 2>/dev/null || true
  aws s3api delete-bucket-tagging --bucket "${bucket}" 2>/dev/null || true
  aws s3api delete-bucket-lifecycle --bucket "${bucket}" 2>/dev/null || true
  aws s3api delete-bucket-encryption --bucket "${bucket}" 2>/dev/null || true
}

delete_version_batch() {
  local bucket="$1"
  local kind="$2"
  local query="$3"

  local count payload
  count=$(aws s3api list-object-versions --bucket "${bucket}" --query "length(${kind})" --output text 2>/dev/null || echo 0)
  [[ "${count}" == "None" || -z "${count}" ]] && count=0
  if (( count == 0 )); then
    echo 0
    return 0
  fi

  payload=$(aws s3api list-object-versions \
    --bucket "${bucket}" \
    --query "{Objects: ${query}, Quiet: true}" \
    --output json)

  aws s3api delete-objects --bucket "${bucket}" --delete "${payload}" >/dev/null
  echo "${count}"
}

# Delete all object versions and delete markers before bucket deletion.
empty_bucket_versions() {
  local bucket="$1"
  local attempts=0

  aws s3 rm "s3://${bucket}" --recursive 2>/dev/null || true

  while (( attempts < MAX_BUCKET_RETRIES )); do
    local deleted_versions deleted_markers
    deleted_versions=$(delete_version_batch "${bucket}" "Versions" 'Versions[].{Key:Key,VersionId:VersionId}')
    deleted_markers=$(delete_version_batch "${bucket}" "DeleteMarkers" 'DeleteMarkers[].{Key:Key,VersionId:VersionId}')

    if (( deleted_versions == 0 && deleted_markers == 0 )); then
      return 0
    fi

    attempts=$((attempts + 1))
  done

  echo "WARN: Could not fully empty bucket versions after ${MAX_BUCKET_RETRIES} passes: ${bucket}" >&2
  return 1
}

TARGET_REGION="$(current_region)"

# For S3 buckets in the current region: empty and delete until none remain.
for ((pass = 1; pass <= MAX_BUCKET_PASSES; pass++)); do
  progress=0
  buckets=$(aws s3api list-buckets --query 'Buckets[].Name' --output text 2>/dev/null || true)
  [[ -z "${buckets}" ]] && break

  for bucket in ${buckets}; do
    bregion="$(bucket_region "${bucket}")"
    [[ "${bregion}" != "${TARGET_REGION}" ]] && continue

    progress=1
    delete_bucket_configs "${bucket}"
    empty_bucket_versions "${bucket}" || true

    if aws s3api delete-bucket --bucket "${bucket}" >/dev/null 2>&1; then
      echo -e "s3\tbucket\t${bucket}"
    else
      echo "WARN: Bucket still exists (possibly locked or in use): ${bucket}" >&2
    fi
  done

  if (( progress == 0 )); then
    break
  fi
done

echo -n ""
