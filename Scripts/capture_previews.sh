#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p output/previews
DEVICE="$(xcrun simctl list devices available --json | python3 -c '
import json,sys,os
runtime=os.environ.get("MAIVERSE_SIM_RUNTIME")
devices=[d for key,group in json.load(sys.stdin)["devices"].items() if not runtime or key==runtime for d in group if d.get("isAvailable") and "iPhone" in d["name"]]
devices.sort(key=lambda d: ("Pro" not in d["name"], d["name"]))
if not devices: raise SystemExit("No available iPhone simulator")
print(devices[0]["udid"])
')"
echo "Rendering actual SwiftUI app on simulator $DEVICE"
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl ui "$DEVICE" appearance dark
xcrun simctl status_bar "$DEVICE" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
TEST_STATUS=0
xcodebuild -project DragonIsland.xcodeproj -scheme DragonIsland \
  -configuration Debug -sdk iphonesimulator -destination "platform=iOS Simulator,id=$DEVICE" \
  -derivedDataPath build/Simulator CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build \
  > build/simulator.log 2>&1 || { tail -80 build/simulator.log; exit 1; }
xcrun simctl install "$DEVICE" build/Simulator/Build/Products/Debug-iphonesimulator/DragonIsland.app
for THEME in dark light; do
  for PAGE in world characters tasks alarms detail gallery-chibi gallery-standing about; do
    xcrun simctl terminate "$DEVICE" com.dragonisle.prototype.app >/dev/null 2>&1 || true
    xcrun simctl launch "$DEVICE" com.dragonisle.prototype.app --maiverse-capture "--preview-$PAGE" "--appearance-$THEME" --scene-black
    sleep 3
    xcrun simctl io "$DEVICE" screenshot "output/previews/$PAGE-$THEME.png"
  done
done
for SCENE in meadow night; do
  for PAGE in about tasks; do
    xcrun simctl terminate "$DEVICE" com.dragonisle.prototype.app >/dev/null 2>&1 || true
    xcrun simctl launch "$DEVICE" com.dragonisle.prototype.app --maiverse-capture "--preview-$PAGE" --appearance-light "--scene-$SCENE"
    sleep 3
    xcrun simctl io "$DEVICE" screenshot "output/previews/$PAGE-scene-$SCENE.png"
  done
done
mkdir -p output/verification
python3 -c 'import time;print(time.time())' > output/verification/video-start-unix.txt
xcrun simctl io "$DEVICE" recordVideo --codec=h264 output/verification/system-island-motion.mp4 > build/video-capture.log 2>&1 &
VIDEO_PID=$!
trap 'kill -INT "$VIDEO_PID" 2>/dev/null || true' EXIT
xcodebuild -project DragonIsland.xcodeproj -scheme DragonIsland \
  -configuration Debug -destination "platform=iOS Simulator,id=$DEVICE" \
  -derivedDataPath build/Simulator -resultBundlePath build/InterfaceTests.xcresult \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test \
  > build/interface-tests.log 2>&1 || TEST_STATUS=$?
xcrun xcresulttool export attachments --path build/InterfaceTests.xcresult --output-path output/ui-test-attachments
python3 Scripts/build_qa_contacts.py
kill -INT "$VIDEO_PID" 2>/dev/null || true
wait "$VIDEO_PID" || true
trap - EXIT
cp build/interface-tests.log output/verification/interface-tests.log
python3 - <<'PY'
from pathlib import Path
for line in Path('build/interface-tests.log').read_text(errors='replace').splitlines():
    if line.startswith('Test Suite ') or 'Executed ' in line or '** TEST ' in line:
        print(line)
PY
xcrun simctl spawn "$DEVICE" log show --last 10m --style compact --predicate '(process == "liveactivitiesd" OR process == "chronod" OR process == "DragonIslandWidget" OR process == "SpringBoard") AND (eventMessage CONTAINS[c] "dragonisle" OR eventMessage CONTAINS[c] "budget" OR eventMessage CONTAINS[c] "archive" OR eventMessage CONTAINS[c] "memory")' > output/verification/live-activity-system.log 2>&1 || true
xcrun simctl spawn "$DEVICE" log show --last 15m --style compact --predicate 'subsystem CONTAINS[c] "AlarmKit" OR (eventMessage CONTAINS[c] "dragonisle" AND eventMessage CONTAINS[c] "alarm")' > output/verification/alarm-system.log 2>&1 || true
APP_DATA="$(xcrun simctl get_app_container "$DEVICE" com.dragonisle.prototype.app data)"
if [[ -f "$APP_DATA/Documents/motion-capture.json" ]]; then
  cp "$APP_DATA/Documents/motion-capture.json" output/verification/motion-capture.json
fi
if [[ -f "$APP_DATA/Documents/alarm-system-state.json" ]]; then
  cp "$APP_DATA/Documents/alarm-system-state.json" output/verification/alarm-system-state.json
fi
if [[ "$TEST_STATUS" != "0" ]]; then
  python3 - <<'PY'
from pathlib import Path
lines=Path('build/interface-tests.log').read_text(errors='replace').splitlines()
for i,line in enumerate(lines):
    if 'error:' in line:
        print('\n'.join(lines[max(0,i-4):i+3]))
print('\n'.join(lines[-60:]))
PY
  exit "$TEST_STATUS"
fi
xcrun swiftc -O Scripts/analyze_motion_video.swift -o build/analyze-motion-video
VIDEO_STATUS=0
build/analyze-motion-video output/verification/system-island-motion.mp4 output/verification || VIDEO_STATUS=$?
python3 - <<'PY'
from pathlib import Path
for name in ('video-timing.json', 'motion-capture.json', 'motion-travel.json', 'pose-continuity.json'):
    path=Path('output/verification')/name
    if path.exists():
        print(name, path.read_text())
PY
if [[ "$VIDEO_STATUS" != "0" ]]; then exit "$VIDEO_STATUS"; fi
xcrun simctl shutdown "$DEVICE"
if [[ "$TEST_STATUS" != "0" ]]; then tail -100 build/interface-tests.log; exit "$TEST_STATUS"; fi
