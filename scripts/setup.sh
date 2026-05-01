#!/bin/bash
# One-time setup after cloning talking-heads.
# Usage: ./scripts/setup.sh
set -e

cd "$(git rev-parse --show-toplevel)"

# Verify required tools
for tool in xcodegen xcodebuild; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "[setup] missing $tool — install via Homebrew (brew install xcodegen) or Xcode" >&2
    exit 1
  fi
done

# Install pre-commit hook (symlink so script edits propagate)
ln -sf ../../scripts/git/pre_commit_hook.sh .git/hooks/pre-commit
echo "[setup] installed .git/hooks/pre-commit → scripts/git/pre_commit_hook.sh"

# Generate Xcode project from project.yml
xcodegen generate
echo "[setup] generated TalkingHeads.xcodeproj"

echo "[setup] done. Open TalkingHeads.xcodeproj in Xcode."
