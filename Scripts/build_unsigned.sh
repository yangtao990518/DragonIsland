#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script needs macOS + Xcode. On Windows, use GitHub Actions as described in README.md." >&2
  exit 1
fi
command -v xcodegen >/dev/null || { echo "Missing XcodeGen; run brew install xcodegen" >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo "Missing Xcode" >&2; exit 1; }

python3 Scripts/prepare_assets.py
xcodegen generate --spec project.yml
mkdir -p build output
xcodebuild -project DragonIsland.xcodeproj -scheme DragonIsland \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build 2>&1 | tee build/build.log

APP="$ROOT/build/DerivedData/Build/Products/Release-iphoneos/DragonIsland.app"
test -d "$APP/PlugIns/DragonIslandWidget.appex"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || { echo "Invalid app version: $VERSION" >&2; exit 1; }
IPA_NAME="mAIverse-V${VERSION}-unsigned.ipa"
IPA_PATH="$ROOT/output/$IPA_NAME"
PACKAGE_DIR="$(mktemp -d "$ROOT/build/package.XXXXXX")"
trap 'rm -rf "$PACKAGE_DIR"' EXIT
mkdir -p "$PACKAGE_DIR/Payload"
ditto "$APP" "$PACKAGE_DIR/Payload/DragonIsland.app"
rm -f "$IPA_PATH"
(cd "$PACKAGE_DIR" && /usr/bin/zip -q -r "$IPA_PATH" Payload)
python3 Scripts/verify_ipa.py "$IPA_PATH"
cp docs/WINDOWS_INSTALL.md output/INSTALL_README.md
shasum -a 256 "output/$IPA_NAME" > output/SHA256SUMS.txt
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'version=%s\n' "$VERSION" >> "$GITHUB_OUTPUT"
fi
echo "Ready: output/$IPA_NAME (unsigned; must be signed with its widget extension)."
