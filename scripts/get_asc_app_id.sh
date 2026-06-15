#!/usr/bin/env bash
# Resolve this app's App Store Connect id from its bundle id (project.yml is the bundle-id source of truth) and print it.
# `source` this file, then call `get_asc_app_id <jwt>` (jwt from mint_asc_jwt).

get_asc_app_id() {
	local jwt="$1" yml bundle
	yml="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/project.yml"
	bundle="$(sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER:[[:space:]]*//p' "$yml" | head -1)"
	curl -gfsS -H "Authorization: Bearer $jwt" \
		"https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]=$bundle&limit=1" |
		jq -r '.data[0].id // empty'
}
