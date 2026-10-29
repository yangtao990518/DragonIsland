#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p output/island-review
python3 - <<'PY'
import json,os,time
from pathlib import Path
Path('output/island-review/recording.json').write_text(json.dumps({
    'recordStartUnix':time.time(),'commit':os.environ['GITHUB_SHA'],
    'device':os.environ['DEVICE_ID'],'scope':'actual iOS Simulator SpringBoard, not a mockup',
    'physicalDeviceVerified':False},indent=2))
PY
xcrun simctl io "$DEVICE_ID" recordVideo --codec=h264 output/island-review/system-island-full.mp4 > build/island-recording.log 2>&1 &
VIDEO_PID=$!
trap 'kill -INT "$VIDEO_PID" 2>/dev/null || true' EXIT
TEST_STATUS=0
xcodebuild -project DragonIsland.xcodeproj -scheme DragonIsland -configuration Debug \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath build/IslandReview \
  -resultBundlePath build/IslandReview.xcresult \
  -only-testing:DragonInterfaceTests/DanceIslandInterfaceTests \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 180 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test-without-building 2>&1 | tee build/island-interface.log || TEST_STATUS=$?
kill -INT "$VIDEO_PID" 2>/dev/null || true
wait "$VIDEO_PID" || true
trap - EXIT
xcrun xcresulttool export attachments --path build/IslandReview.xcresult --output-path output/island-review/screenshots || true
xcrun simctl io "$DEVICE_ID" screenshot output/island-review/simulator-final.png
APP_DATA="$(xcrun simctl get_app_container "$DEVICE_ID" com.dragonisle.prototype.app data)"
if [[ -f "$APP_DATA/Documents/dance-island-capture.json" ]]; then
  cp "$APP_DATA/Documents/dance-island-capture.json" output/island-review/dance-island-capture.json
fi
xcrun simctl spawn "$DEVICE_ID" log show --last 8m --style compact \
  --predicate '(process == "liveactivitiesd" OR process == "chronod" OR process == "DragonIslandWidget") AND (eventMessage CONTAINS[c] "dragonisle" OR eventMessage CONTAINS[c] "budget" OR eventMessage CONTAINS[c] "memory")' \
  > output/island-review/live-activity-system.log 2>&1 || true
exit "$TEST_STATUS"
