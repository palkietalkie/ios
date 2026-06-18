#!/usr/bin/env bash
# Submit the editable App Store version for APP REVIEW (the actual store submission, distinct from TestFlight beta review in submit-build.sh). Attaches the VALID build to the version, then drives Apple's reviewSubmissions flow (create submission -> add the version as an item -> set submitted=true).
#
# Usage: submit-app-review.sh --version <N> [--wait]
#   --wait: poll while a just-uploaded build is still PROCESSING (can't attach until VALID).
# Idempotent: reuses an in-progress reviewSubmission and skips re-adding/re-submitting.
#
# PREREQUISITE (Apple gates this): App Privacy must be PUBLISHED and the version's metadata/screenshots complete, or the final submit returns a validation error listing what's missing. TestFlight (submit-build.sh) has no such gate; App Store review does.
set -euo pipefail

dir="$(dirname "$0")"
# shellcheck source=/dev/null
. "$dir/mint_asc_jwt.sh"
# shellcheck source=/dev/null
. "$dir/get_asc_app_id.sh"

ASC="https://api.appstoreconnect.apple.com"
# Apple's editable pre-release states; a version in any of these can have a build attached + be submitted.
EDITABLE='PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY'
version=""
wait_processing=0
while [ $# -gt 0 ]; do
	case "$1" in
	--version) version="${2:?--version needs a value}" && shift 2 ;;
	--wait) wait_processing=1 && shift ;;
	*) echo "submit-app-review: unknown arg $1" >&2 && exit 2 ;;
	esac
done

jwt="$(mint_asc_jwt)"
get() { curl -gfsS -H "Authorization: Bearer $jwt" "$ASC$1"; }
post() { curl -gfsS -X POST -H "Authorization: Bearer $jwt" -H "Content-Type: application/json" -d "$2" "$ASC$1"; }
patch() { curl -gfsS -X PATCH -H "Authorization: Bearer $jwt" -H "Content-Type: application/json" -d "$2" "$ASC$1"; }

app_id="$(get_asc_app_id "$jwt")"
[ -n "$app_id" ] || {
	echo "submit-app-review: no app for this bundle id" >&2
	exit 1
}

# Editable version (the one in a pre-release state).
version_id="$(get "/v1/apps/$app_id/appStoreVersions?limit=50&fields[appStoreVersions]=appStoreState,versionString" |
	jq -r --arg states "$EDITABLE" '.data[] | select((.attributes.appStoreState) as $s | ($states | split(" ") | index($s))) | .id' | head -1)"
[ -n "$version_id" ] || {
	echo "submit-app-review: no editable App Store version found" >&2
	exit 1
}

# Resolve the VALID build for --version (or newest), polling out Apple processing with --wait. Same shape as submit-build.sh.
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
		echo "submit-app-review: build ${version:-newest} not VALID yet; pass --wait." >&2
		exit 1
	}
	[ "$(date +%s)" -gt "$deadline" ] && {
		echo "submit-app-review: timed out waiting for processing." >&2
		exit 1
	}
	echo "[review] build still processing — waiting 30s …"
	sleep 30
done
echo "[review] version $version_id ← build $build_id"

# Attach the build to the version (idempotent; PATCH to the same build is a no-op).
patch "/v1/appStoreVersions/$version_id/relationships/build" \
	"{\"data\":{\"type\":\"builds\",\"id\":\"$build_id\"}}" >/dev/null

# Reuse an open reviewSubmission if one exists, else create one. COMPLETE/CANCELING ones are terminal — ignore them.
sub_id="$(get "/v1/apps/$app_id/reviewSubmissions?filter[platform]=IOS&fields[reviewSubmissions]=state" |
	jq -r '[.data[] | select(.attributes.state | IN("READY_FOR_REVIEW","WAITING_FOR_REVIEW","IN_REVIEW","UNRESOLVED_ISSUES"))][0].id // empty')"
if [ -z "$sub_id" ]; then
	sub_id="$(post "/v1/reviewSubmissions" \
		"{\"data\":{\"type\":\"reviewSubmissions\",\"attributes\":{\"platform\":\"IOS\"},\"relationships\":{\"app\":{\"data\":{\"type\":\"apps\",\"id\":\"$app_id\"}}}}}" |
		jq -r '.data.id')"
	echo "[review] created reviewSubmission $sub_id"
else
	echo "[review] reusing open reviewSubmission $sub_id"
fi

# Add the version as an item (a 409/conflict means it's already attached — fine).
post "/v1/reviewSubmissionItems" \
	"{\"data\":{\"type\":\"reviewSubmissionItems\",\"relationships\":{\"reviewSubmission\":{\"data\":{\"type\":\"reviewSubmissions\",\"id\":\"$sub_id\"}},\"appStoreVersion\":{\"data\":{\"type\":\"appStoreVersions\",\"id\":\"$version_id\"}}}}}" \
	>/dev/null 2>&1 || echo "[review] version already an item (ok)"

# Submit. Apple validates here: if App Privacy isn't published or metadata is incomplete, this returns the list of blockers.
state="$(patch "/v1/reviewSubmissions/$sub_id" \
	"{\"data\":{\"type\":\"reviewSubmissions\",\"id\":\"$sub_id\",\"attributes\":{\"submitted\":true}}}" |
	jq -r '.data.attributes.state // empty')"
echo "[review] submitted for App Review → ${state:-(see response above)}"
