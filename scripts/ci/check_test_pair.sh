#!/usr/bin/env bash
# Refuses a PR whose changed source files have no paired test file (CLAUDE.md "Every fix ships with a test").
#
# Convention enforced:
#   PalkieTalkie/**/Foo.swift  ⇄  PalkieTalkieTests/**/*Foo*.swift   (the test must EXIST)
#
# iOS tests live in a flat PalkieTalkieTests/ directory and don't mirror source paths, so the rule is "any test file whose filename contains the source basename counts." Loose match deliberately; tighter pairing would force a 1:1 split that doesn't match how iOS tests group features (e.g. SessionController has multiple *Tests.swift files).
#
# Requires the paired test to EXIST, not to be CHANGED in the same PR. "Must be changed" false-positives on every pure refactor (file move, type split into Type+Feature.swift extensions, component extraction) where behavior — and therefore the right test — is unchanged. Real regressions are still caught: a behavior change that isn't tested breaks the existing test, and CI runs the full suite. This guard's job is "no source ships with zero test coverage."
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
	# A `Type+Feature.swift` extension file is conventionally tested through the base type's tests (`TypeTests.swift`), not a `Type+FeatureTests.swift`. Match against the part before '+' so e.g. BackendEndpoints+Catalog.swift is satisfied by BackendEndpointsTests.swift, and SessionController+Observers.swift by SessionControllerTests.swift.
	match="${base%%+*}"
	if ! find PalkieTalkieTests -name "*${match}*.swift" -print -quit 2>/dev/null | grep -q .; then
		MISSING_PAIRS+=("  ${f}  →  PalkieTalkieTests/*${match}*.swift  (no test for ${match}; create one)")
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
