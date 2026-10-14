#!/usr/bin/env bash
set -euo pipefail
mkdir -p device-evidence/before/databases
trap 'status=$?; if [ "$status" -ne 0 ]; then adb logcat -d > device-evidence/failure-logcat.txt || true; adb exec-out screencap -p > device-evidence/failure-screen.png || true; fi' EXIT
wait_for_ui() {
  local expected="$1" name="$2"
  for attempt in $(seq 1 10); do
    echo "Waiting for $name readiness (attempt $attempt)"
    timeout 20s adb shell uiautomator dump /sdcard/business-upgrade-ui.xml >/dev/null 2>&1 || true
    adb exec-out cat /sdcard/business-upgrade-ui.xml > "device-evidence/$name-ui.xml" || true
    if grep -Fq "$expected" "device-evidence/$name-ui.xml"; then return 0; fi
    sleep 1
  done
  adb logcat -d > "device-evidence/$name-startup-logcat.txt"
  echo "Timed out waiting for $name to finish opening its database" >&2
  return 1
}
adb install ../baseline-debug/app-debug.apk
adb shell am start -W -n au.monster.tracker.plus/au.monster.tracker.MainActivity
wait_for_ui 'CANS REMAINING' baseline
adb shell am force-stop au.monster.tracker.plus
# Copy a quiescent database and its journal without depending on Android tar output.
for suffix in '' '-wal' '-shm'; do
  name="monster-offline.db$suffix"
  if adb shell run-as au.monster.tracker.plus test -f "databases/$name"; then
    adb exec-out run-as au.monster.tracker.plus cat "databases/$name" > "device-evidence/before/databases/$name"
  fi
done
python3 ../scripts/flutter/seed-upgrade.py device-evidence/before/databases/monster-offline.db
adb push device-evidence/before/databases/monster-offline.db /data/local/tmp/legacy-upgrade.db
adb shell run-as au.monster.tracker.plus rm -f databases/monster-offline.db-wal databases/monster-offline.db-shm
adb shell run-as au.monster.tracker.plus cp /data/local/tmp/legacy-upgrade.db databases/monster-offline.db
# Convert the seeded installation to the actual non-debuggable 1.6.3 baseline.
# This preserves the same records and enables an exact release-to-release update.
baseline_release=$(find ../baseline-release -name '*.apk' -print -quit)
adb install -r "$baseline_release"
adb shell am start -W -n au.monster.tracker.plus/au.monster.tracker.MainActivity
wait_for_ui 'CANS REMAINING' baseline-release
adb shell am force-stop au.monster.tracker.plus
# The actual shipped Flutter release must read the populated records before update.
adb install -r ../baseline-flutter-release/Business-Tracker-2.0.0.apk
adb shell am start -W -n au.monster.tracker.plus/au.monster.tracker.MainActivity
wait_for_ui 'Your business at a glance' flutter-2.0.0
adb exec-out screencap -p > device-evidence/baseline-flutter-2.0.0.png
adb shell am force-stop au.monster.tracker.plus
adb shell cmd connectivity airplane-mode enable
adb shell svc wifi disable
adb shell svc data disable
adb shell settings get global airplane_mode_on | tr -d '\r' | grep -qx 1
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb logcat -c
adb shell am start -W -n au.monster.tracker.plus/au.monster.tracker.MainActivity
wait_for_ui 'Record sale' direct-release
python3 - <<'CHECK'
import xml.etree.ElementTree as ET,re
root=ET.parse('device-evidence/direct-release-ui.xml').getroot()
labels=[node.get(k,'') for node in root.iter() for k in ('text','content-desc')]
assert any(re.search(r'(?<![0-9])25(?![0-9])',label) for label in labels), labels
print('Release 2.0.0 → release 2.0.1 shows the original 25 units before any test build runs.')
CHECK
adb exec-out screencap -p > device-evidence/direct-release-upgrade.png
adb logcat -d > device-evidence/direct-release-logcat.txt
! grep -E 'FATAL EXCEPTION|Unhandled Exception' device-evidence/direct-release-logcat.txt
# Same-certificate instrumented build reads the migration already made by release.
# Flutter drive otherwise uninstalls the app during cleanup; keep it for persistence proof.
timeout 8m flutter drive --no-dds --keep-app-running --driver=test_driver/integration_test.dart --target=integration_test/upgrade_test.dart --dart-define=EXPECT_LEGACY=true
# Prove the uninstrumented release APK also updates in place and launches.
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb logcat -c
adb shell am start -W -n au.monster.tracker.plus/au.monster.tracker.MainActivity
wait_for_ui 'My skincare business' release-restart
adb exec-out screencap -p > device-evidence/release-upgrade.png
adb logcat -d > device-evidence/release-logcat.txt
! grep -E 'FATAL EXCEPTION|Unhandled Exception' device-evidence/release-logcat.txt
# Fresh-install path has no old database and must remain empty.
# This clear is on the disposable CI emulator only, after the upgrade proof.
adb shell pm clear au.monster.tracker.plus
timeout 8m flutter drive --no-dds --keep-app-running --driver=test_driver/integration_test.dart --target=integration_test/upgrade_test.dart --dart-define=EXPECT_LEGACY=false
