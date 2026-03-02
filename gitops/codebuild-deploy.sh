#!/bin/bash
# Usage: ./codebuild-deploy.sh
# Custom: GITHUB_REPO=myorg/myrepo GITHUB_BRANCH=develop CONNECTION_NAME=my-connection ./codebuild-deploy.sh
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration - can be overridden via environment variables
GITHUB_REPO="${GITHUB_REPO:-daws25/GitOps}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
PROJECT_NAME="${PROJECT_NAME:-gitops-webhook}"
STACK_NAME="${STACK_NAME:-$PROJECT_NAME}"
BUILDSPEC_PATH="${BUILDSPEC_PATH:-gitops/buildspec.yaml}"
CONNECTION_NAME="${CONNECTION_NAME:-connection-github-daws25}"

echo "Deploying CodeBuild project with GitHub webhook"
echo "GitHub Repo: $GITHUB_REPO"
echo "GitHub Branch: $GITHUB_BRANCH"
echo "Project Name: $PROJECT_NAME"
echo "Stack Name: $STACK_NAME"
echo "BuildSpec: $BUILDSPEC_PATH"
echo "Connection Name: $CONNECTION_NAME"
echo ""

echo "===== Looking up CodeConnection ====="
CONNECTION_ARN=$(aws codeconnections list-connections \
    --provider-type GitHub \
    --query "Connections[?ConnectionName=='${CONNECTION_NAME}'].ConnectionArn" \
    --output text 2>/dev/null || true)

if [ -z "$CONNECTION_ARN" ]; then
    echo "ERROR: Connection '$CONNECTION_NAME' not found!"
    echo ""
    echo "Available GitHub connections:"
    aws codeconnections list-connections \
        --provider-type GitHub \
        --query 'Connections[].{Name:ConnectionName,Status:ConnectionStatus}' \
        --output table 2>/dev/null || echo "  None found"
    echo ""
    echo "Create a connection in the AWS Console:"
    echo "  https://console.aws.amazon.com/codesuite/settings/connections"
    exit 1
fi

CONNECTION_STATUS=$(aws codeconnections list-connections \
    --provider-type GitHub \
    --query "Connections[?ConnectionName=='${CONNECTION_NAME}'].ConnectionStatus" \
    --output text 2>/dev/null || echo "UNKNOWN")

echo "Connection ARN: $CONNECTION_ARN"
echo "Connection Status: $CONNECTION_STATUS"

if [ "$CONNECTION_STATUS" != "AVAILABLE" ]; then
    echo ""
    echo "WARNING: Connection is not AVAILABLE (status: $CONNECTION_STATUS)"
    echo "Activate it at: https://console.aws.amazon.com/codesuite/settings/connections"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi
echo ""

echo "===== Deploying Stack ====="
PARAMS="GitHubRepo=$GITHUB_REPO GitHubBranch=$GITHUB_BRANCH ProjectName=$PROJECT_NAME BuildSpec=$BUILDSPEC_PATH ConnectionArn=$CONNECTION_ARN"

aws cloudformation deploy \
    --stack-name $STACK_NAME \
    --template-file $DIR/codebuild.cform.yaml \
    --parameter-overrides $PARAMS \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset

echo ""
echo "===== Deployment Complete ====="
echo ""

echo "Stack outputs:"
aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs' \
    --output table

echo ""
echo "To view build logs:"
echo "  aws logs tail /aws/codebuild/$PROJECT_NAME --follow"
echo ""
echo "To manually trigger a build:"
echo "  aws codebuild start-build --project-name $PROJECT_NAME"
