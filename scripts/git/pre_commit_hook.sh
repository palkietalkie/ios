#!/bin/bash
# Pre-commit hook for palkietalkie/ios.
# Install: ln -sf ../../scripts/git/pre_commit_hook.sh .git/hooks/pre-commit
set -e

cd "$(git rev-parse --show-toplevel)"

STAGED=$(git diff --cached --name-only --diff-filter=ACM)

require() {
	local tool=$1 install=$2
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "[pre-commit] missing $tool. Install: $install"
		exit 1
	fi
}

# Markdown lint
MD_STAGED=$(echo "$STAGED" | grep -E "\.md$" || true)
if [ -n "$MD_STAGED" ]; then
	require markdownlint "brew install markdownlint-cli"
	echo "[pre-commit] markdownlint..."
	echo "$MD_STAGED" | xargs markdownlint
fi

# Shell format (auto-fix) + lint (fail on violations)
SH_STAGED=$(echo "$STAGED" | grep -E "\.sh$" || true)
if [ -n "$SH_STAGED" ]; then
	require shfmt "brew install shfmt"
	require shellcheck "brew install shellcheck"

	echo "[pre-commit] shfmt (auto-fix)..."
	echo "$SH_STAGED" | xargs shfmt -w
	echo "$SH_STAGED" | xargs git add # re-stage formatted files

	echo "[pre-commit] shellcheck..."
	echo "$SH_STAGED" | xargs shellcheck
fi

# Swift format (auto-fix) + lint (fail on violations)
SWIFT_STAGED=$(echo "$STAGED" | grep -E "\.swift$" || true)
if [ -n "$SWIFT_STAGED" ]; then
	require swiftformat "brew install swiftformat"
	require swiftlint "brew install swiftlint"

	echo "[pre-commit] swiftformat (auto-fix)..."
	echo "$SWIFT_STAGED" | xargs swiftformat
	echo "$SWIFT_STAGED" | xargs git add # re-stage formatted files

	echo "[pre-commit] swiftlint (strict, staged files only)..."
	echo "$SWIFT_STAGED" | xargs swiftlint lint --strict --quiet
fi

# Regenerate Xcode project if project.yml changed
if echo "$STAGED" | grep -qx "project.yml"; then
	echo "[pre-commit] project.yml changed → xcodegen generate"
	xcodegen generate
fi

# Build sanity check if any Swift file or project.yml is staged
if echo "$STAGED" | grep -qE "(\.swift$|^project\.yml$)"; then
	echo "[pre-commit] xcodebuild..."
	xcodebuild \
		-project PalkieTalkie.xcodeproj \
		-scheme PalkieTalkie \
		-destination 'generic/platform=iOS Simulator' \
		build -quiet
fi
