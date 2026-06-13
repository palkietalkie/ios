#!/usr/bin/env bash
# Enforces the Swift convention: every .swift file name is UpperCamelCase (PascalCase),
# whether it holds a type, an extension, or a free function. The file name is not a Swift
# identifier, so it follows the file convention (PascalCase), independent of the symbol inside
# (types PascalCase, free functions camelCase). e.g. `func resolveRootDestination` lives in
# `ResolveRootDestination.swift`.
#
# Skips generated files.
set -e

REPO="$(git rev-parse --show-toplevel)"
cd "$REPO"

violations=()
while IFS= read -r f; do
	case "$f" in
	*/Generated/*) continue ;;
	esac
	base=$(basename "$f")
	if [[ "${base:0:1}" =~ [a-z] ]]; then
		violations+=("  $f")
	fi
done < <(find PalkieTalkie PalkieTalkieTests -name "*.swift")

if [ "${#violations[@]}" -gt 0 ]; then
	echo "::error::Swift file names must be UpperCamelCase (PascalCase). Lowercase-first files:" >&2
	printf '%s\n' "${violations[@]}" >&2
	echo "Rename: git mv -f path/foo.swift path/Foo.swift  (the function/type inside keeps its own casing)." >&2
	exit 1
fi

echo "[pascal-case] OK"
