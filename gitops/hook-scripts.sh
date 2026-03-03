#!/usr/bin/env bash
# Print all details received by a webhook event on AWS CodeBuild
# Usage: Called from buildspec.yaml

echo "===== WebHook Received Event ====="
echo ""

echo "===== CodeBuild Build Info ====="
echo "Build ID: $CODEBUILD_BUILD_ID"
echo "Build Number: $CODEBUILD_BUILD_NUMBER"
echo "Build ARN: $CODEBUILD_BUILD_ARN"
echo "Initiator: $CODEBUILD_INITIATOR"
echo ""

echo "===== Source Info ====="
echo "Source Version: $CODEBUILD_SOURCE_VERSION"
echo "Resolved Source Version: $CODEBUILD_RESOLVED_SOURCE_VERSION"
echo "Source Repo URL: $CODEBUILD_SOURCE_REPO_URL"
echo ""

echo "===== Webhook Details ====="
echo "Event Type: $CODEBUILD_WEBHOOK_EVENT"
echo "Trigger: $CODEBUILD_WEBHOOK_TRIGGER"
echo "Head Ref: $CODEBUILD_WEBHOOK_HEAD_REF"
echo "Base Ref: $CODEBUILD_WEBHOOK_BASE_REF"
echo "Actor Account ID: $CODEBUILD_WEBHOOK_ACTOR_ACCOUNT_ID"
echo "Merge Commit: $CODEBUILD_WEBHOOK_MERGE_COMMIT"
echo "Previous Commit: $CODEBUILD_WEBHOOK_PREV_COMMIT"
echo ""

echo "===== Git Info ====="
if command -v git &> /dev/null && [ -d .git ]; then
    git log -1 --pretty=format:"Commit: %H%nAuthor: %an <%ae>%nDate: %ad%nMessage: %s%n" || true
    echo ""
    echo "Branches:"
    git branch -a 2>/dev/null || true
else
    echo "Git not available or not a git repository"
fi
echo ""

echo "===== All Environment Variables ====="
env | sort

