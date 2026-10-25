#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p output/previews
DEVICE="$(xcrun simctl list devices available --json | python3 -c '
import json,sys
devices=[d for group in json.load(sys.stdin)["devices"].values() for d in group if d.get("isAvailable") and "iPhone" in d["name"]]
devices.sort(key=lambda d: ("Pro" not in d["name"], d["name"]))
if not devices: raise SystemExit("No available iPhone simulator")
print(devices[0]["udid"])
')"
echo "Rendering actual SwiftUI app on simulator $DEVICE"
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl ui "$DEVICE" appearance dark
xcrun simctl status_bar "$DEVICE" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcodebuild -project DragonIsland.xcodeproj -scheme DragonIsland \
  -configuration Debug -sdk iphonesimulator -destination "platform=iOS Simulator,id=$DEVICE" \
  -derivedDataPath build/Simulator CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build \
  > build/simulator.log 2>&1 || { tail -80 build/simulator.log; exit 1; }
xcrun simctl install "$DEVICE" build/Simulator/Build/Products/Debug-iphonesimulator/DragonIsland.app
for PAGE in world characters about; do
  xcrun simctl terminate "$DEVICE" com.dragonisle.prototype.app >/dev/null 2>&1 || true
  xcrun simctl launch "$DEVICE" com.dragonisle.prototype.app --maiverse-capture "--preview-$PAGE"
  sleep 3
  xcrun simctl io "$DEVICE" screenshot "output/previews/$PAGE.png"
done
xcrun simctl shutdown "$DEVICE"
