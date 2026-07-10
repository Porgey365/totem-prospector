#!/bin/bash

# Script to download firmware from latest GitHub Actions run
# Usage: ./download-firmware.sh [branch]

set -e

REPO="Porgey365/totem-prospector"

# Use specified branch/commit or default to current git commit
if [ -z "$1" ]; then
    # Try to get current commit from git
    if command -v git &> /dev/null && [ -d ".git" ]; then
        COMMIT=$(git rev-parse HEAD 2>/dev/null)
        if [ -z "$COMMIT" ]; then
            COMMIT=""  # Fallback if git fails
        fi
        BRANCH=""  # Empty branch when using commit
        AUTO_DETECTED=" (auto-detected from current git commit: ${COMMIT:0:7})"
    else
        BRANCH="main"  # Fallback if git not available
        COMMIT=""
        AUTO_DETECTED=""
    fi
else
    # Check if the argument is a commit hash (7-40 hex characters)
    if [[ "$1" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
        COMMIT="$1"
        BRANCH=""  # Empty branch when using commit
        AUTO_DETECTED=" (using specific commit: ${COMMIT:0:7})"
    else
        BRANCH="$1"
        COMMIT=""
        AUTO_DETECTED=" (using specific branch: $BRANCH)"
    fi
fi

OUTPUT_DIR="firmware"

echo "Fetching latest workflow run for branch: $BRANCH$AUTO_DETECTED"

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed."
    echo "Install it from: https://cli.github.com/"
    exit 1
fi

# Get the latest successful workflow run for the branch or commit
if [ -n "$COMMIT" ]; then
    # Expand short commit hash to full hash if needed
    if [[ "$COMMIT" =~ ^[0-9a-fA-F]{7,40}$ ]] && [ ${#COMMIT} -lt 40 ]; then
        FULL_COMMIT=$(git rev-parse "$COMMIT^{commit}" 2>/dev/null || echo "")
        if [ -n "$FULL_COMMIT" ]; then
            COMMIT="$FULL_COMMIT"
        fi
    fi

    # Search by commit hash
    RUN_ID=$(gh run list \
        --repo "$REPO" \
        --workflow build.yml \
        --limit 50 \
        --json databaseId,headSha,conclusion \
        --jq ".[] | select(.headSha == \"$COMMIT\" and .conclusion == \"success\") | .databaseId" | head -n 1)
else
    # Search by branch
    RUN_ID=$(gh run list \
        --repo "$REPO" \
        --branch "$BRANCH" \
        --workflow build.yml \
        --limit 50 \
        --json databaseId,conclusion \
        --jq '.[0] | select(.conclusion == "success") | .databaseId')
fi

if [ -z "$RUN_ID" ]; then
    if [ -n "$COMMIT" ]; then
        echo "Error: No successful workflow runs found for commit ${COMMIT:0:7}"
    else
        echo "Error: No successful workflow runs found for branch $BRANCH"
    fi
    exit 1
fi

echo "Found workflow run: $RUN_ID"
echo "Downloading artifacts..."

# Clean and create output directory
if [ -d "$OUTPUT_DIR" ]; then
    echo "Cleaning existing firmware directory..."
    rm -rf "$OUTPUT_DIR"
fi
mkdir -p "$OUTPUT_DIR"

# Download all artifacts from the run
gh run download "$RUN_ID" \
    --repo "$REPO" \
    --dir "$OUTPUT_DIR"

echo ""
echo "✓ Firmware downloaded successfully to: $OUTPUT_DIR/"
echo ""
echo "Contents:"
ls -lh "$OUTPUT_DIR"
echo ""
echo "To flash firmware, use: ./flash-firmware.sh [dongle|left|right|trackball|reset]"
