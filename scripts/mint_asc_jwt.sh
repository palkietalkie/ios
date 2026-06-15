#!/usr/bin/env bash
# Mint a short-lived ES256 JWT for the App Store Connect API and print it. Pure openssl — no Python/uv, no backend repo.
# Key from $APPLE_ASC_API_KEY_BASE64 (base64 .p8, as in ios/.env + the GH secret) or $APPLE_ASC_PRIVATE_KEY (raw .p8 text).
# `source` this file, then call `mint_asc_jwt`.

mint_asc_jwt() {
	local key_id="P4HBNA5WD6" issuer="129df326-897e-414d-acda-0e89b6b4f653"
	local key_file now header claims signing_input der rlen r slen s sig
	key_file="$(mktemp)"
	if [ -n "${APPLE_ASC_PRIVATE_KEY:-}" ]; then
		printf '%s' "$APPLE_ASC_PRIVATE_KEY" >"$key_file"
	elif [ -n "${APPLE_ASC_API_KEY_BASE64:-}" ]; then
		printf '%s' "$APPLE_ASC_API_KEY_BASE64" | base64 --decode >"$key_file"
	else
		rm -f "$key_file"
		echo "mint_asc_jwt: set APPLE_ASC_API_KEY_BASE64 or APPLE_ASC_PRIVATE_KEY" >&2
		return 2
	fi

	b64url() { openssl base64 -e -A | tr '+/' '-_' | tr -d '='; }
	now="$(date +%s)"
	header="$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$key_id" | b64url)"
	claims="$(printf '{"iss":"%s","iat":%d,"exp":%d,"aud":"appstoreconnect-v1"}' "$issuer" "$now" "$((now + 1200))" | b64url)"
	signing_input="${header}.${claims}"
	der="$(printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$key_file" | xxd -p | tr -d '\n')"
	rm -f "$key_file"
	# openssl emits a DER ECDSA signature (SEQUENCE{INTEGER r, INTEGER s}); JWS ES256 wants raw r||s, 32 bytes each. Parse the DER (single-byte lengths are safe for P-256) and zero-pad.
	der="${der#30??}"
	der="${der#02}"
	rlen=$((16#${der:0:2}))
	r="${der:2:$((rlen * 2))}"
	der="${der:$((2 + rlen * 2))}"
	der="${der#02}"
	slen=$((16#${der:0:2}))
	s="${der:2:$((slen * 2))}"
	r="${r#00}" && while [ "${#r}" -lt 64 ]; do r="0$r"; done && r="${r: -64}"
	s="${s#00}" && while [ "${#s}" -lt 64 ]; do s="0$s"; done && s="${s: -64}"
	sig="$(printf '%s%s' "$r" "$s" | xxd -r -p | b64url)"
	printf '%s.%s' "$signing_input" "$sig"
}
