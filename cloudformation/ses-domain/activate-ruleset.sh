#!/bin/bash
# Usage: ./activate-ruleset.sh
# Custom: DOMAIN_NAME=example.com ./activate-ruleset.sh
set -e
source "$(dirname "${BASH_SOURCE[0]}")/vars.sh"

RULESET_NAME="${DOMAIN_NAME}-ruleset"

echo "Activating SES receipt rule set for domain: $DOMAIN_NAME"
echo "Rule Set: $RULESET_NAME"
echo ""

echo "===== Current Active Rule Set ====="
aws ses describe-active-receipt-rule-set \
    --query 'Metadata.Name' \
    --output text 2>/dev/null || echo "None"
echo ""

echo "===== Activating Rule Set ====="
echo "Note: This will deactivate any other active rule set in your account."
aws ses set-active-receipt-rule-set --rule-set-name $RULESET_NAME

echo ""
echo "===== Activation Complete ====="
echo "Receipt rule set activated! You can now receive emails at *@$DOMAIN_NAME"
echo ""
echo "Emails will be stored in S3 bucket."
echo ""
echo "To deactivate (stop receiving emails):"
echo "  aws ses set-active-receipt-rule-set"
