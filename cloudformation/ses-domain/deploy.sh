#!/bin/bash
# Usage: ./deploy.sh
# Custom: DOMAIN_NAME=example.com ZONE_ID=ZXXXX ./deploy.sh
set -e
source "$(dirname "${BASH_SOURCE[0]}")/vars.sh"

echo "Deploying SES stack for domain: $DOMAIN_NAME"
echo "Using Route 53 Zone ID: $ZONE_ID"
echo "Stack name: $STACK_NAME"
echo "Environment ID: $ENV_ID"
echo "Packaging S3 bucket: $TEMP_S3_BUCKET"
echo ""

# Create S3 bucket for CloudFormation packaging if it doesn't exist
echo "Ensuring S3 bucket exists for template packaging..."
if ! aws s3 ls s3://$TEMP_S3_BUCKET 2>/dev/null; then
    echo "Creating S3 bucket: $TEMP_S3_BUCKET"
    if [ "$(aws configure get region)" = "us-east-1" ]; then
        aws s3 mb s3://$TEMP_S3_BUCKET
    else
        aws s3 mb s3://$TEMP_S3_BUCKET --region $(aws configure get region)
    fi
else
    echo "S3 bucket already exists: $TEMP_S3_BUCKET"
fi
echo ""

# Create temporary directory for packaged templates
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "Packaging CloudFormation templates..."
aws cloudformation package \
    --template-file $DIR/template.cform.yaml \
    --s3-bucket $TEMP_S3_BUCKET \
    --output-template-file $TEMP_DIR/packaged.yaml

echo ""
echo "Deploying stack..."

PARAMS="EnvId=$ENV_ID DomainName=$DOMAIN_NAME HostedZoneId=$ZONE_ID"

aws cloudformation deploy \
    --stack-name $STACK_NAME \
    --template-file $TEMP_DIR/packaged.yaml \
    --parameter-overrides $PARAMS \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset

echo ""
echo "===== Deployment Complete ====="
echo ""

# Save outputs to JSON file for other scripts
save_outputs

echo ""
echo "Stack outputs:"
aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs' \
    --output table

echo ""
echo "Outputs saved to: $OUTPUT_FILE"

# Wait for DNS propagation and DKIM verification
if [ "$WAIT_FOR_DNS" -gt 0 ]; then
    echo ""
    echo "===== Waiting for DNS Propagation ====="
    echo "Waiting $WAIT_FOR_DNS seconds for DNS records to propagate..."
    
    elapsed=0
    while [ $elapsed -lt $WAIT_FOR_DNS ]; do
        # Check DKIM status
        dkim_status=$(aws ses get-identity-dkim-attributes \
            --identities $DOMAIN_NAME \
            --query "DkimAttributes.$DOMAIN_NAME.DkimVerificationStatus" \
            --output text 2>/dev/null || echo "PENDING")
        
        if [ "$dkim_status" = "Success" ]; then
            echo ""
            echo "DKIM verified successfully!"
            break
        fi
        
        printf "\rWaiting... %ds / %ds (DKIM: %s)" $elapsed $WAIT_FOR_DNS "$dkim_status"
        sleep 15
        elapsed=$((elapsed + 15))
    done
    echo ""
fi

# Activate receipt rule set if enabled
if [ "$ACTIVATE_RULESET" = "true" ]; then
    echo ""
    echo "===== Activating Receipt Rule Set ====="
    RULESET_NAME="${DOMAIN_NAME}-ruleset"
    echo "Activating: $RULESET_NAME"
    echo "Note: This will deactivate any other active rule set in your account."
    aws ses set-active-receipt-rule-set --rule-set-name $RULESET_NAME
    echo "Receipt rule set activated! You can receive emails at *@$DOMAIN_NAME"
else
    echo ""
    echo "To receive emails, activate the receipt rule set manually:"
    echo "  aws ses set-active-receipt-rule-set --rule-set-name ${DOMAIN_NAME}-ruleset"
fi

echo ""
echo "===== Verifying Email Addresses (Sandbox Mode) ====="
echo "Note: While in SES sandbox mode, both sender and recipient must be verified."
echo "Sending verification emails to: noreply@$DOMAIN_NAME, test@$DOMAIN_NAME"
aws ses verify-email-identity --email-address "noreply@$DOMAIN_NAME" 2>/dev/null || true
aws ses verify-email-identity --email-address "test@$DOMAIN_NAME" 2>/dev/null || true
echo "Verification emails sent! Check inboxes and click the verification links."
echo ""
echo "To verify additional addresses:"
echo "  aws ses verify-email-identity --email-address user@$DOMAIN_NAME"

echo ""
echo "Note: DKIM verification may take a few minutes. Check status with:"
echo "  ./status.sh"