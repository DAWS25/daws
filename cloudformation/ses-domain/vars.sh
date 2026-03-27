#!/bin/bash
# Shared configuration variables for SES CloudFormation scripts
# Source this file in other scripts: source "$(dirname "${BASH_SOURCE[0]}")/vars.sh"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# ===== Configuration Variables =====
DOMAIN_NAME=${DOMAIN_NAME:-"daws25.org"}
DOMAIN_PREFIX=$(echo "$DOMAIN_NAME" | sed 's/\./-/g')
ENV_ID=${ENV_ID:-"$DOMAIN_PREFIX"}
STACK_NAME=${STACK_NAME:-"${DOMAIN_PREFIX}-ses"}
ZONE_ID=${ZONE_ID:-"Z0921914152XH19OIIQKY"}
ACTIVATE_RULESET=${ACTIVATE_RULESET:-"true"}
WAIT_FOR_DNS=${WAIT_FOR_DNS:-60}  # Seconds to wait for DNS propagation

# Temporary S3 bucket for CloudFormation package (should be created before deployment)
TEMP_S3_BUCKET=${TEMP_S3_BUCKET:-"${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}-cfn-templates"}

# ===== Output File =====
OUTPUT_FILE="$DIR/output-${DOMAIN_PREFIX}.json"

# ===== Helper Functions =====

# Save stack outputs to JSON file
save_outputs() {
    echo "Saving stack outputs to $OUTPUT_FILE"
    aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0]' \
        --output json > "$OUTPUT_FILE"
}

# Load value from output file
# Usage: get_output "OutputKey"
get_output() {
    local key=$1
    if [ -f "$OUTPUT_FILE" ]; then
        jq -r ".Outputs[] | select(.OutputKey==\"$key\") | .OutputValue" "$OUTPUT_FILE"
    else
        echo ""
    fi
}

# Load parameter from output file
# Usage: get_parameter "ParameterKey"
get_parameter() {
    local key=$1
    if [ -f "$OUTPUT_FILE" ]; then
        jq -r ".Parameters[] | select(.ParameterKey==\"$key\") | .ParameterValue" "$OUTPUT_FILE"
    else
        echo ""
    fi
}

# Load variables from output file if it exists
load_from_output() {
    if [ -f "$OUTPUT_FILE" ]; then
        local saved_domain=$(get_parameter "DomainName")
        local saved_zone=$(get_parameter "HostedZoneId")
        local saved_stack=$(jq -r '.StackName' "$OUTPUT_FILE")
        
        # Use saved values if not overridden by environment
        if [ -n "$saved_domain" ] && [ "$DOMAIN_NAME" = "daws25.org" ]; then
            DOMAIN_NAME=$saved_domain
        fi
        if [ -n "$saved_zone" ] && [ "$ZONE_ID" = "Z0921914152XH19OIIQKY" ]; then
            ZONE_ID=$saved_zone
        fi
        if [ -n "$saved_stack" ] && [ "$saved_stack" != "null" ]; then
            STACK_NAME=$saved_stack
        fi
        return 0
    fi
    return 1
}
