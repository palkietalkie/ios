#!/usr/bin/env bash
# Refuses a PR whose changed source files don't also change their paired test files.
#
# Convention enforced (matches CLAUDE.md "Every fix ships with a test"):
#   PalkieTalkie/**/Foo.swift  ⇄  PalkieTalkieTests/**/*Foo*.swift
#
# iOS tests live in a flat PalkieTalkieTests/ directory and don't mirror source paths, so the rule is "any test file
# whose filename contains the source basename counts." Loose match deliberately; tighter pairing would force a 1:1
# split that doesn't match how iOS tests group features (e.g. SessionController has multiple *Tests.swift files).
#
# Skips: PalkieTalkie/Generated/* (generated), scripts/, .github/, Assets.xcassets/, Localizable.xcstrings, Info.plist.

set -e

BASE_REF="${1:-origin/main}"

git fetch --quiet --depth=200 origin main 2>/dev/null || true

CHANGED=$(git diff --name-only "${BASE_REF}"...HEAD)
if [ -z "$CHANGED" ]; then
	echo "[test-pair] no changes vs ${BASE_REF}"
	exit 0
fi

MISSING_PAIRS=()
while IFS= read -r f; do
	[ -z "$f" ] && continue
	case "$f" in
	# Skip non-source paths
	PalkieTalkieTests/* | scripts/* | .github/* | docs/*) continue ;;
	# Skip generated + non-code resources
	PalkieTalkie/Generated/*) continue ;;
	PalkieTalkie/Assets.xcassets/* | PalkieTalkie/Localizable.xcstrings | PalkieTalkie/Info.plist) continue ;;
	# Only check Swift files under the app target
	PalkieTalkie/*.swift) ;;
	*) continue ;;
	esac

	base=$(basename "$f" .swift)
	# Any test file whose basename contains the source basename counts as the pair.
	if ! printf '%s\n' "$CHANGED" | grep -qE "^PalkieTalkieTests/.*${base}.*\.swift$"; then
		if find PalkieTalkieTests -name "*${base}*.swift" -print -quit 2>/dev/null | grep -q .; then
			MISSING_PAIRS+=("  ${f}  (modified)  →  PalkieTalkieTests/*${base}*.swift  (exists but unchanged in PR)")
		else
			MISSING_PAIRS+=("  ${f}  (modified)  →  PalkieTalkieTests/*${base}*.swift  (no test for ${base}; create one)")
		fi
	fi
done <<<"$CHANGED"

if [ "${#MISSING_PAIRS[@]}" -gt 0 ]; then
	echo "::error::Source files changed without their paired test files:"
	printf '%s\n' "${MISSING_PAIRS[@]}"
	echo
	echo "Per CLAUDE.md: 'Every fix ships with a test that fails before the fix and passes after.'"
	echo "Fix: add or update a test in PalkieTalkieTests/ whose filename includes the source basename, and include it in this PR."
	exit 1
fi

echo "[test-pair] OK"
