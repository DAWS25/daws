#!/bin/bash
# Usage: ./request-production.sh
# Custom: MAIL_TYPE=PROMOTIONAL WEBSITE_URL=https://example.com ./request-production.sh
set -e
source "$(dirname "${BASH_SOURCE[0]}")/vars.sh"

# Default values - can be overridden via environment variables
MAIL_TYPE="${MAIL_TYPE:-TRANSACTIONAL}"
WEBSITE_URL="${WEBSITE_URL:-https://$DOMAIN_NAME}"
USE_CASE="${USE_CASE:-Sending transactional emails such as password resets, order confirmations, and notifications to users of our application.}"
CONTACT_LANGUAGE="${CONTACT_LANGUAGE:-EN}"

echo "Requesting SES production access for domain: $DOMAIN_NAME"
echo "Stack name: $STACK_NAME"
echo "Mail Type: $MAIL_TYPE"
echo "Website URL: $WEBSITE_URL"
echo ""

echo "===== Checking Current Account Status ====="
aws sesv2 get-account \
    --query '{ProductionAccess: ProductionAccessEnabled, SendingEnabled: SendingEnabled}' \
    --output table 2>/dev/null || echo "Unable to get account status"
echo ""

echo "===== Submitting Production Access Request ====="
echo "Use Case: $USE_CASE"
echo ""

aws sesv2 put-account-details \
    --mail-type "$MAIL_TYPE" \
    --website-url "$WEBSITE_URL" \
    --use-case-description "$USE_CASE" \
    --contact-language "$CONTACT_LANGUAGE" \
    --production-access-enabled

echo ""
echo "===== Request Submitted ====="
echo ""
echo "AWS will review your request and respond via email (usually within 24 hours)."
echo ""
echo "Check your account status with:"
echo "  aws sesv2 get-account"
