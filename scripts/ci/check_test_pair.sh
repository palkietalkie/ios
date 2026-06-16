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

CHANGED=$(git diff --name-only --diff-filter=ACMR "${BASE_REF}"...HEAD)
if [ -z "$CHANGED" ]; then
	echo "[test-pair] no changes vs ${BASE_REF}"
	exit 0
fi

MISSING_PAIRS=()
while IFS= read -r f; do
	[ -z "$f" ] && continue
	case "$f" in
	PalkieTalkieTests/* | scripts/* | .github/* | docs/*) continue ;;
	PalkieTalkie/Generated/*) continue ;;
	PalkieTalkie/Assets.xcassets/* | PalkieTalkie/Localizable.xcstrings | PalkieTalkie/Info.plist) continue ;;
	PalkieTalkie/*.swift) ;;
	*) continue ;;
	esac

	base=$(basename "$f" .swift)
	# Escape ERE metacharacters in the basename so grep matches it literally. Without this, a '+' in a source name (e.g. SessionController+Recall.swift) is read as a quantifier and the real paired test never matches — the find() glob below does, producing a false "exists but unchanged".
	base_re=$(printf '%s' "$base" | sed -E 's/[][(){}.*+?|^$\\]/\\&/g')
	if ! printf '%s\n' "$CHANGED" | grep -qE "^PalkieTalkieTests/.*${base_re}.*\.swift$"; then
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
