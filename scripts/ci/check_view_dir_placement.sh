#!/usr/bin/env bash
# Enforces that PalkieTalkie/Views/ holds only SwiftUI views and their view models —
# not pure helpers. A file under Views/ is allowed iff it either:
#   - imports SwiftUI (it's a view / view component), or
#   - is named *ViewModel.swift (MVVM: Foundation-only @Observable, lives next to its view).
#
# Foundation-only free functions / codecs / adapters (e.g. GoalsCodec, LocalizedGoalName,
# ResolveRootDestination) are NOT views and belong in Formatting/ Localization/ Navigation/ etc.
# This is the placement guard that catches them drifting back into Views/.
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
	# A view model is allowed (MVVM convention) regardless of imports.
	case "$(basename "$f")" in
	*ViewModel.swift) continue ;;
	esac
	# Otherwise it must be a SwiftUI view.
	if ! grep -qE "^import SwiftUI" "$f"; then
		violations+=("  $f")
	fi
done < <(find PalkieTalkie/Views -name "*.swift")

if [ "${#violations[@]}" -gt 0 ]; then
	echo "::error::Views/ may contain only SwiftUI views (import SwiftUI) or *ViewModel.swift. Misplaced non-view files:" >&2
	printf '%s\n' "${violations[@]}" >&2
	echo "Move pure helpers out of Views/: string/codec → Formatting/, slug→label → Localization/, routing → Navigation/." >&2
	echo "  git mv PalkieTalkie/Views/Foo.swift PalkieTalkie/<Dir>/Foo.swift  (call sites resolve automatically — no intra-module imports)." >&2
	exit 1
fi

echo "[view-dir-placement] OK"
