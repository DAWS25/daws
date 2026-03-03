#!/bin/bash
# Usage: ./delete.sh
# Custom: DOMAIN_NAME=example.com ./delete.sh
set -e
source "$(dirname "${BASH_SOURCE[0]}")/vars.sh"

# Load saved configuration if available
if load_from_output; then
    echo "Using saved configuration from: $OUTPUT_FILE"
fi

echo "Deleting SES stack: $STACK_NAME"
echo "Domain: $DOMAIN_NAME"
echo ""

# First, deactivate any active receipt rule set (silently ignore if none active)
echo "Deactivating receipt rule set (if one is active)..."
aws ses set-active-receipt-rule-set 2>/dev/null || echo "(No active rule set to deactivate)"

aws cloudformation delete-stack --stack-name $STACK_NAME

echo "Waiting for stack deletion..."
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME

# Remove the output file
if [ -f "$OUTPUT_FILE" ]; then
    rm "$OUTPUT_FILE"
    echo "Removed output file: $OUTPUT_FILE"
fi

echo "Stack deleted successfully"
