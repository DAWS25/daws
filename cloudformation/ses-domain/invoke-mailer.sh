#!/bin/bash
# Usage: ./invoke-mailer.sh [to_email]
# Custom: DOMAIN_NAME=example.com ./invoke-mailer.sh recipient@gmail.com
set -e
source "$(dirname "${BASH_SOURCE[0]}")/vars.sh"

# Load saved configuration if available
load_from_output 2>/dev/null || true

FUNCTION_NAME="${ENV_ID}-fn-mailer"
TO_EMAIL=${1:-"test@${DOMAIN_NAME}"}
FROM_EMAIL=${FROM_EMAIL:-"noreply@${DOMAIN_NAME}"}
SUBJECT=${SUBJECT:-"Test Email from ${DOMAIN_NAME}"}
BODY=${BODY:-"This is a test email sent from ${DOMAIN_NAME} via Amazon SES."}

echo "Invoking mailer function: $FUNCTION_NAME"
echo "From: $FROM_EMAIL"
echo "To: $TO_EMAIL"
echo "Subject: $SUBJECT"
echo ""

PAYLOAD=$(cat <<EOF
{
  "to": "$TO_EMAIL",
  "from": "$FROM_EMAIL",
  "subject": "$SUBJECT",
  "body": "$BODY"
}
EOF
)

RESPONSE=$(aws lambda invoke \
    --function-name "$FUNCTION_NAME" \
    --payload "$PAYLOAD" \
    --cli-binary-format raw-in-base64-out \
    /dev/stdout 2>/dev/null)

echo "Response:"
echo "$RESPONSE" | jq .
