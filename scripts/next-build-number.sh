#!/usr/bin/env bash
# Print the next TestFlight build number — highest already on App Store Connect + 1.
#
# The build number is the app's CFBundleVersion (an iOS / App Store Connect concern), so it lives in the iOS repo. Pure shell — openssl (ES256 JWT) + curl + jq, no Python/uv. Used by scripts/release.sh and .github/workflows/deploy.yml. ASC is the source of truth for what's already uploaded; derive from there, never git (commit count diverges from upload count).
#
# Auth: the ASC API .p8 via --key-path <file> or $APPLE_ASC_PRIVATE_KEY (the key text). Key id, issuer id, and bundle id are non-secret identifiers.
set -euo pipefail

KEY_ID="P4HBNA5WD6"
ISSUER_ID="129df326-897e-414d-acda-0e89b6b4f653"
ASC="https://api.appstoreconnect.apple.com"

# Bundle id's source of truth is project.yml (what Xcode signs) — read it, don't restate it.
project_yml="$(cd "$(dirname "$0")/.." && pwd)/project.yml"
BUNDLE_ID="$(sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER:[[:space:]]*//p' "$project_yml" | head -1)"
: "${BUNDLE_ID:?could not read PRODUCT_BUNDLE_IDENTIFIER from $project_yml}"

key_path=""
while [ $# -gt 0 ]; do
	case "$1" in
	--key-path) key_path="${2:?--key-path needs a value}" && shift 2 ;;
	*)
		echo "next-build-number: unknown arg $1" >&2
		exit 2
		;;
	esac
done

if [ -z "$key_path" ]; then
	: "${APPLE_ASC_PRIVATE_KEY:?pass --key-path <.p8> or set APPLE_ASC_PRIVATE_KEY}"
	key_path="$(mktemp)"
	trap 'rm -f "$key_path"' EXIT
	printf '%s' "$APPLE_ASC_PRIVATE_KEY" >"$key_path"
fi

b64url() { openssl base64 -e -A | tr '+/' '-_' | tr -d '='; }

now="$(date +%s)"
header="$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$KEY_ID" | b64url)"
claims="$(printf '{"iss":"%s","iat":%d,"exp":%d,"aud":"appstoreconnect-v1"}' "$ISSUER_ID" "$now" "$((now + 1200))" | b64url)"
signing_input="${header}.${claims}"

# openssl emits a DER ECDSA signature (SEQUENCE{INTEGER r, INTEGER s}); JWS ES256 wants raw r||s, 32 bytes each. Parse the DER (single-byte lengths are safe for P-256) and zero-pad.
der="$(printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$key_path" | xxd -p | tr -d '\n')"
der="${der#30??}" # SEQUENCE tag + length byte
der="${der#02}"   # INTEGER tag (r)
rlen=$((16#${der:0:2}))
r="${der:2:$((rlen * 2))}"
der="${der:$((2 + rlen * 2))}"
der="${der#02}" # INTEGER tag (s)
slen=$((16#${der:0:2}))
s="${der:2:$((slen * 2))}"
r="${r#00}" && while [ "${#r}" -lt 64 ]; do r="0$r"; done && r="${r: -64}"
s="${s#00}" && while [ "${#s}" -lt 64 ]; do s="0$s"; done && s="${s: -64}"
sig="$(printf '%s%s' "$r" "$s" | xxd -r -p | b64url)"
jwt="${signing_input}.${sig}"

app_id="$(curl -gfsS -H "Authorization: Bearer $jwt" \
	"$ASC/v1/apps?filter[bundleId]=$BUNDLE_ID&limit=1" | jq -r '.data[0].id // empty')"
[ -n "$app_id" ] || {
	echo "next-build-number: no app found for bundle $BUNDLE_ID" >&2
	exit 1
}
highest="$(curl -gfsS -H "Authorization: Bearer $jwt" \
	"$ASC/v1/builds?filter[app]=$app_id&limit=200&fields[builds]=version" |
	jq -r '.data[].attributes.version' | grep -E '^[0-9]+$' | sort -n | tail -1)"
echo "$((${highest:-0} + 1))"
