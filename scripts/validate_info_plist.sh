#!/usr/bin/env bash
# Runs as xcodegen's postGenCommand. Catches the failure mode where xcodegen wrote unresolved `${VAR}` placeholders into Info.plist because the required env vars were unset at generate time. Without this guard, the app silently ships with empty `CLERK_PUBLISHABLE_KEY` / `BACKEND_URL` / `PERSONAPLEX_HOST` and surfaces deep-stack auth errors ("Clerk Native API is disabled") instead of the real root cause.

set -euo pipefail

PLIST="${1:-PalkieTalkie/Info.plist}"

if [[ ! -f "$PLIST" ]]; then
	echo "[validate_info_plist] $PLIST not found" >&2
	exit 1
fi

# Look for any unresolved `${...}` template. There should be none after xcodegen.
if grep -nE '\$\{[A-Z_]+' "$PLIST"; then
	echo "[validate_info_plist] FAIL: $PLIST contains unresolved \${VAR} placeholders." >&2
	echo "[validate_info_plist] Required env vars (set via boot.sh or 'set -a; source ios/.env; set +a'): BACKEND_URL, PERSONAPLEX_HOST, CLERK_PUBLISHABLE_KEY." >&2
	exit 1
fi

# Belt-and-suspenders: confirm the keys we depend on exist and are non-empty.
for key in CLERK_PUBLISHABLE_KEY BACKEND_URL PERSONAPLEX_HOST; do
	value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" 2>/dev/null || true)
	if [[ -z "$value" ]]; then
		echo "[validate_info_plist] FAIL: $PLIST :$key is empty. Set the env var before running xcodegen." >&2
		exit 1
	fi
done

echo "[validate_info_plist] OK: $PLIST"
