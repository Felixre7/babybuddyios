#!/usr/bin/env bash
# Runs the XCUITest suite (scheme BabyBuddyUITests) on a dedicated simulator that is erased,
# booted, and shut down again around every run. Same command CI runs; extra xcodebuild arguments
# pass straight through.
#
#   scripts/ui-test.sh [xcodebuild args]
#   scripts/ui-test.sh -only-testing:BabyBuddyUITests/DialogTests/testSignOutCard
#   UI_TEST_DEVICE=CI-BabyBuddy scripts/ui-test.sh -retry-tests-on-failure -test-iterations 2
#
# Erasing covers what the app's own per-launch reset (BB_UITEST, see UITests/UITestCase.swift)
# can't: notification permission, the alternate app icon, Live Activities, delivered banners.
#
# The device is named "BabyBuddy UI Tests" ($UI_TEST_DEVICE to change), never "iPhone…", so no
# other script or human picks it — a foreign launch kills a UI run. It is an iPhone 17 Pro on the
# newest iOS runtime installed when it was created: the suite needs iOS 26+.
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${UI_TEST_DEVICE:-BabyBuddy UI Tests}"
RESULT=build/UITests.xcresult

UDID=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
for devs in json.load(sys.stdin)["devices"].values():
    for d in devs:
        if d["name"] == sys.argv[1]:
            print(d["udid"]); sys.exit()
' "$DEVICE")
if [ -z "$UDID" ]; then
  RUNTIME=$(xcrun simctl list runtimes available --json | python3 -c '
import json, sys
rts = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS"]
rts.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
print(rts[-1]["identifier"])')
  UDID=$(xcrun simctl create "$DEVICE" "iPhone 17 Pro" "$RUNTIME")
  echo "created simulator '$DEVICE' ($UDID)"
fi

trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true' EXIT
xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
xcrun simctl erase "$UDID"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null

rm -rf "$RESULT"
set +e
# Unsigned on purpose: the store and the keychain both fall back to app-only locations without the
# App Group entitlement, which is all an in-app UI test touches.
xcodebuild -project BabyBuddy.xcodeproj -scheme BabyBuddyUITests -destination "id=$UDID" \
  -resultBundlePath "$RESULT" \
  test CODE_SIGNING_ALLOWED=NO -quiet "$@"
STATUS=$?
set -e

# -quiet hides the totals, and would hide an empty -only-testing filter passing with zero tests.
[ -d "$RESULT" ] || { echo "::error::no result bundle — the build failed before any test ran"; exit 1; }
xcrun xcresulttool get test-results summary --path "$RESULT" --format json | python3 -c '
import json, sys
s = json.load(sys.stdin)
total, passed, failed, skipped = s["totalTestCount"], s["passedTests"], s["failedTests"], s["skippedTests"]
print(f"UI tests: {passed} passed, {failed} failed, {skipped} skipped (of {total})")
for t in s.get("testFailures", []):
    print("  FAIL {}: {}".format(t.get("testName"), t.get("failureText")))
if total == 0:
    print("::error::zero UI tests ran — check the -only-testing filter"); sys.exit(1)
' || exit 1
exit $STATUS
