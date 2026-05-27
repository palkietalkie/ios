#!/bin/bash
# One-time setup after cloning palkietalkie/ios.
# Usage: ./scripts/setup.sh
set -e

cd "$(git rev-parse --show-toplevel)"

# Verify required tools (xcodebuild ships with Xcode; the rest are Homebrew)
if ! command -v xcodebuild >/dev/null 2>&1; then
	echo "[setup] missing xcodebuild — install Xcode" >&2
	exit 1
fi
if ! command -v uv >/dev/null 2>&1; then
	echo "[setup] missing uv — install with: brew install uv (needed for generate_api_types.py)" >&2
	exit 1
fi

# Install Homebrew tools used by the pre-commit hook (idempotent)
# xcode-build-server: bridges sourcekit-lsp ↔ .xcodeproj (we don't ship a Package.swift, so the LSP can't find the project without it — symptoms are bogus "Cannot find type X" errors on otherwise-compiling code)
HOMEBREW_TOOLS=(xcodegen xcode-build-server markdownlint-cli swiftformat swiftlint shfmt shellcheck)
MISSING=()
for tool in "${HOMEBREW_TOOLS[@]}"; do
	bin=$tool
	[ "$tool" = "markdownlint-cli" ] && bin=markdownlint
	command -v "$bin" >/dev/null 2>&1 || MISSING+=("$tool")
done
if [ ${#MISSING[@]} -gt 0 ]; then
	echo "[setup] installing Homebrew tools: ${MISSING[*]}"
	brew install "${MISSING[@]}"
else
	echo "[setup] all Homebrew tools already installed"
fi

# Wire git's hooks path to scripts/git so the pre-commit script in this repo runs as-is. Matches backend + website setup.
git config core.hooksPath scripts/git
echo "[setup] git config core.hooksPath=scripts/git (pre-commit lives at scripts/git/pre-commit)"

# Generate Xcode project from project.yml
xcodegen generate
echo "[setup] generated PalkieTalkie.xcodeproj"

# Generate sourcekit-lsp ↔ Xcode bridge. Points at boot.sh's project-local DerivedData so the LSP reads the same index store boot.sh populates. Machine-local (gitignored).
xcode-build-server config -scheme PalkieTalkie -project PalkieTalkie.xcodeproj >/dev/null
python3 -c "import json,sys; p='buildServer.json'; d=json.load(open(p)); d['build_root']='$(pwd)/.build/DerivedData'; json.dump(d, open(p,'w'), indent='\t')"
echo "[setup] wrote buildServer.json (sourcekit-lsp bridge)"

# Download iOS simulator runtime if missing (matches project.yml deployment target)
TARGET_MAJOR=$(awk '/iOS:/ {gsub(/"/, "", $2); split($2, v, "."); print v[1]; exit}' project.yml)
if ! xcrun simctl list runtimes | grep -q "iOS ${TARGET_MAJOR}"; then
	echo "[setup] iOS ${TARGET_MAJOR} simulator runtime missing — downloading (~7GB, 10–30 min)…"
	xcodebuild -downloadPlatform iOS
else
	echo "[setup] iOS ${TARGET_MAJOR} simulator runtime already installed"
fi

echo "[setup] done. Open PalkieTalkie.xcodeproj in Xcode."
