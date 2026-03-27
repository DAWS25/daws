#!/bin/bash
# Usage: ./status.sh
# Custom: DOMAIN_NAME=example.com ./status.sh
set -e
source "$(dirname "${BASH_SOURCE[0]}")/vars.sh"

# Load saved configuration if available
if load_from_output; then
    echo "Using saved configuration from: $OUTPUT_FILE"
    echo ""
fi

echo "===== Stack Status ====="
echo "Stack Name: $STACK_NAME"
echo "Domain: $DOMAIN_NAME"
aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "Stack does not exist"

echo ""
echo "===== SES Domain Identity Status ====="
aws ses get-identity-verification-attributes \
    --identities $DOMAIN_NAME \
    --query 'VerificationAttributes' \
    --output table 2>/dev/null || echo "Domain not configured"

echo ""
echo "===== DKIM Status ====="
aws ses get-identity-dkim-attributes \
    --identities $DOMAIN_NAME \
    --query 'DkimAttributes' \
    --output table 2>/dev/null || echo "DKIM not configured"

# Show additional info from saved outputs
if [ -f "$OUTPUT_FILE" ]; then
    echo ""
    echo "===== Saved Outputs ====="
    echo "SMTP Endpoint: $(get_output 'SMTPEndpoint')"
    echo "Inbound SMTP: $(get_output 'InboundSMTPEndpoint')"
    echo "Config Set: $(get_output 'ConfigurationSetName')"
fi
