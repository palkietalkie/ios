#!/usr/bin/env bash
# Submit an uploaded build for external TestFlight (Beta App) Review — the step that actually puts a build in front of external testers (upload alone leaves it un-submitted). Self-contained — no backend repo dependency.
#
# Usage: submit-build.sh --version <N> [--wait]
#   --wait: a just-uploaded build sits in PROCESSING ~5-15 min and can't be submitted until VALID; poll until it is.
# Idempotent: adds the build to every external beta group and submits for review; a build already in review is a no-op.
set -euo pipefail

dir="$(dirname "$0")"
# shellcheck source=/dev/null
. "$dir/mint_asc_jwt.sh"
# shellcheck source=/dev/null
. "$dir/get_asc_app_id.sh"

ASC="https://api.appstoreconnect.apple.com"
version=""
wait_processing=0
while [ $# -gt 0 ]; do
	case "$1" in
	--version) version="${2:?--version needs a value}" && shift 2 ;;
	--wait) wait_processing=1 && shift ;;
	*)
		echo "submit-build: unknown arg $1" >&2
		exit 2
		;;
	esac
done

jwt="$(mint_asc_jwt)"
get() { curl -gfsS -H "Authorization: Bearer $jwt" "$ASC$1"; }
post() { curl -gfsS -X POST -H "Authorization: Bearer $jwt" -H "Content-Type: application/json" -d "$2" "$ASC$1"; }

app_id="$(get_asc_app_id "$jwt")"
[ -n "$app_id" ] || {
	echo "submit-build: no app found for this bundle id" >&2
	exit 1
}

# Resolve the build id for --version (or newest), requiring VALID. With --wait, poll while Apple is still processing.
deadline=$(($(date +%s) + 30 * 60))
while :; do
	json="$(get "/v1/builds?filter[app]=$app_id&sort=-uploadedDate&limit=20&fields[builds]=version,processingState")"
	if [ -n "$version" ]; then
		build_id="$(printf '%s' "$json" | jq -r --arg v "$version" '.data[] | select(.attributes.version==$v and .attributes.processingState=="VALID") | .id' | head -1)"
	else
		build_id="$(printf '%s' "$json" | jq -r '[.data[] | select(.attributes.processingState=="VALID")][0].id // empty')"
	fi
	[ -n "$build_id" ] && break
	[ "$wait_processing" = "1" ] || {
		echo "submit-build: build ${version:-(newest)} not VALID (processed) yet; pass --wait to poll." >&2
		exit 1
	}
	[ "$(date +%s)" -gt "$deadline" ] && {
		echo "submit-build: timed out (30 min) waiting for Apple processing." >&2
		exit 1
	}
	echo "[submit] build still processing — waiting 30s …"
	sleep 30
done
echo "[submit] build ${version:-newest VALID} → id $build_id"

# Add to every external beta group (re-adding an already-present build is a no-op).
group_ids="$(get "/v1/apps/$app_id/betaGroups?fields[betaGroups]=name,isInternalGroup" |
	jq -r '.data[] | select(.attributes.isInternalGroup==false) | .id')"
[ -n "$group_ids" ] || {
	echo "submit-build: no external beta group exists — create one in TestFlight first." >&2
	exit 1
}
while IFS= read -r gid; do
	post "/v1/betaGroups/$gid/relationships/builds" "{\"data\":[{\"type\":\"builds\",\"id\":\"$build_id\"}]}" >/dev/null
done <<<"$group_ids"

# Re-submitting a build already in review returns an opaque 422, so detect the "already done" case first.
prior="$(get "/v1/builds/$build_id/betaAppReviewSubmission?fields[betaAppReviewSubmissions]=betaReviewState" |
	jq -r '.data.attributes.betaReviewState // empty')"
if [ -n "$prior" ]; then
	echo "[submit] already in beta review: $prior — nothing to do."
	exit 0
fi
state="$(post "/v1/betaAppReviewSubmissions" \
	"{\"data\":{\"type\":\"betaAppReviewSubmissions\",\"relationships\":{\"build\":{\"data\":{\"type\":\"builds\",\"id\":\"$build_id\"}}}}}" |
	jq -r '.data.attributes.betaReviewState // empty')"
echo "[submit] submitted for Beta App Review → $state"
