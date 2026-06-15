#!/usr/bin/env bash
# Print the next TestFlight build number — highest already on App Store Connect + 1.
#
# The build number is the app's CFBundleVersion (an iOS / App Store Connect concern), so it lives in the iOS repo. ASC is the source of truth for what's already uploaded; derive from there, never git (commit count diverges from upload count). Auth key comes from the environment (see mint_asc_jwt.sh) — no backend repo needed.
set -euo pipefail

dir="$(dirname "$0")"
# shellcheck source=/dev/null
. "$dir/mint_asc_jwt.sh"
# shellcheck source=/dev/null
. "$dir/get_asc_app_id.sh"

jwt="$(mint_asc_jwt)"
app_id="$(get_asc_app_id "$jwt")"
[ -n "$app_id" ] || {
	echo "next-build-number: no app found for this bundle id" >&2
	exit 1
}
highest="$(curl -gfsS -H "Authorization: Bearer $jwt" \
	"https://api.appstoreconnect.apple.com/v1/builds?filter[app]=$app_id&limit=200&fields[builds]=version" |
	jq -r '.data[].attributes.version' | grep -E '^[0-9]+$' | sort -n | tail -1)"
echo "$((${highest:-0} + 1))"
