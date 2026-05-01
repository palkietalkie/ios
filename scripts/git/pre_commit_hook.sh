#!/bin/bash
# Pre-commit hook for talking-heads
# Install: ln -sf ../../scripts/git/pre_commit_hook.sh .git/hooks/pre-commit
set -e

cd "$(git rev-parse --show-toplevel)"

STAGED=$(git diff --cached --name-only --diff-filter=ACM)

# Regenerate Xcode project if project.yml changed
if echo "$STAGED" | grep -qx "project.yml"; then
  echo "[pre-commit] project.yml changed → xcodegen generate"
  xcodegen generate
fi

# Build sanity check if any Swift file or project.yml is staged
if echo "$STAGED" | grep -qE "(\.swift$|^project\.yml$)"; then
  echo "[pre-commit] Building TalkingHeads…"
  xcodebuild \
    -project TalkingHeads.xcodeproj \
    -scheme TalkingHeads \
    -destination 'generic/platform=iOS Simulator' \
    build -quiet
fi
