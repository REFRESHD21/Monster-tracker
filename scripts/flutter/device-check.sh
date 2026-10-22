#!/usr/bin/env bash
set -euo pipefail
mkdir -p device-evidence/before/databases
trap 'status=$?; if [ "$status" -ne 0 ]; then adb logcat -d > device-evidence/failure-logcat.txt || true; adb exec-out screencap -p > device-evidence/failure-screen.png || true; fi' EXIT
dismiss_emulator_system_anr() {
  local xml="$1" point x y
  if ! grep -Eq 'text="(Pixel Launcher|System UI) isn.t responding"' "$xml"; then return 0; fi
  point=$(python3 - "$xml" <<'PY'
import re, sys, xml.etree.ElementTree as ET
root=ET.parse(sys.argv[1]).getroot()
title=next((n.get('text','') for n in root.iter() if "isn't responding" in n.get('text','')), '')
if not (title.startswith('Pixel Launcher') or title.startswith('System UI')):
    raise SystemExit(0)
node=next((n for n in root.iter() if n.get('text')=='Wait'), None)
if node is None: raise SystemExit(0)
m=re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',node.get('bounds',''))
if m is None: raise SystemExit(0)
l,t,r,b=map(int,m.groups())
print((l+r)//2,(t+b)//2)
PY
)
  if [[ -n "$point" ]]; then
    read -r x y <<<"$point"
    echo "Waiting out Android emulator launcher/system UI ANR."
    adb shell input tap "$x" "$y"
    sleep 2
  fi
}
wait_for_ui() {
  local expected="$1" name="$2"
  for attempt in $(seq 1 10); do
    echo "Waiting for $name readiness (attempt $attempt)"
    timeout 20s adb shell uiautomator dump /sdcard/business-upgrade-ui.xml >/dev/null 2>&1 || true
    adb exec-out cat /sdcard/business-upgrade-ui.xml > "device-evidence/$name-ui.xml" || true
    dismiss_emulator_system_anr "device-evidence/$name-ui.xml"
    if grep -Fq "$expected" "device-evidence/$name-ui.xml"; then return 0; fi
    sleep 1
  done
  adb logcat -d > "device-evidence/$name-startup-logcat.txt"
  echo "Timed out waiting for $name to finish opening its database" >&2
  return 1
}
# Hosted emulator transports can drop while Flutter attaches to a new process.
# Retry only before the test body starts; never replay a partially executed test.
drive_checked() {
  local scenario="$1" legacy="$2" attempt status log
  for attempt in 1 2 3; do
    log="device-evidence/drive-$scenario-$attempt.log"
    set +e
    timeout 8m flutter drive --no-dds --keep-app-running --driver=test_driver/integration_test.dart --target=integration_test/upgrade_test.dart --dart-define-from-file=config/google-oauth.json --dart-define="EXPECT_LEGACY=$legacy" 2>&1 | tee "$log"
    status=${PIPESTATUS[0]}
    set -e
    if [ "$status" -eq 0 ]; then return 0; fi
    # Never retry a real test assertion or app exception. Only recover when
    # Flutter/ADB lost the emulator before the integration test began.
    if [ "$attempt" -eq 3 ] || grep -Eq 'I/flutter.*upgrade retains records|EXCEPTION CAUGHT|Test failed|Some tests failed|FATAL EXCEPTION|Unhandled Exception' "$log"; then
      return "$status"
    fi
    if ! grep -Eq 'Service connection disposed|Error waiting for a debug connection: The log reader stopped unexpectedly|adb: device offline|Application failed to start' "$log"; then
      return "$status"
    fi
    echo "Recovering $scenario after a pre-test ADB/emulator disconnect (attempt $attempt); preserving installed data."
    adb kill-server || true
    adb start-server
    if ! timeout 60s adb wait-for-device; then
      echo "Emulator did not reconnect after the ADB reset." >&2
      return "$status"
    fi
    if ! timeout 30s adb shell getprop sys.boot_completed | grep -q '^1
  done
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
adb install -r ../baseline-flutter-release/Business-Tracker-2.1.0.apk
adb shell am start -W -n au.monster.tracker.plus/au.monster.tracker.MainActivity
wait_for_ui 'Your business at a glance' flutter-2.1.0
adb exec-out screencap -p > device-evidence/baseline-flutter-2.1.0.png
adb shell am force-stop au.monster.tracker.plus
# Keep the emulator transport stable during upgrade/restore integration tests.
# Offline-first persistence is asserted by app-level integration and database tests.
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb logcat -c
adb shell am start -W -n au.monster.tracker.plus/au.monster.tracker.MainActivity
wait_for_ui 'Record sale' direct-release
for attempt in $(seq 1 5); do
  timeout 20s adb shell uiautomator dump /sdcard/business-upgrade-inventory.xml >/dev/null 2>&1 || true
  adb exec-out cat /sdcard/business-upgrade-inventory.xml > device-evidence/direct-release-inventory-ui.xml || true
  if grep -Fq 'Units on hand' device-evidence/direct-release-inventory-ui.xml; then break; fi
  adb shell input swipe 100 500 100 120 500
done
python3 - <<'CHECK'
import xml.etree.ElementTree as ET,re
root=ET.parse('device-evidence/direct-release-inventory-ui.xml').getroot()
labels=[node.get(k,'') for node in root.iter() for k in ('text','content-desc')]
assert any('Units on hand' in label for label in labels), labels
assert any(re.search(r'(?<![0-9])25(?![0-9])',label) for label in labels), labels
print('Release 2.1.0 → release 2.2.0 shows the original 25 units before any test build runs.')
CHECK
adb exec-out screencap -p > device-evidence/direct-release-upgrade.png
adb logcat -d > device-evidence/direct-release-logcat.txt
! grep -E 'FATAL EXCEPTION|Unhandled Exception' device-evidence/direct-release-logcat.txt
# Same-certificate instrumented build reads the migration already made by release.
# Flutter drive otherwise uninstalls the app during cleanup; keep it for persistence proof.
drive_checked upgrade true
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
drive_checked empty false

# Exercise the in-app restore screen against a synthetic, checksum-valid
# seven-event business backup. This clear is limited to the disposable emulator.
adb shell pm clear au.monster.tracker.plus >/dev/null
drive_restore() {
  local attempt status log
  for attempt in 1 2 3; do
    log="device-evidence/drive-restore-$attempt.log"
    set +e
    timeout 8m flutter drive --no-dds --keep-app-running --driver=test_driver/integration_test.dart --target=integration_test/restore_test.dart --dart-define-from-file=config/google-oauth.json 2>&1 | tee "$log"
    status=${PIPESTATUS[0]}
    set -e
    if [ "$status" -eq 0 ]; then return 0; fi
    if [ "$attempt" -eq 3 ] || ! grep -Fq 'Service connection disposed' "$log" || grep -Eq 'EXCEPTION CAUGHT|Test failed|Some tests failed' "$log"; then
      adb logcat -d > device-evidence/restore-failure-logcat.txt
      return "$status"
    fi
    echo "Retrying restore test attachment after a pre-test transport disconnect; emulator app data remains disposable."
    timeout 30s adb wait-for-device
    adb shell am force-stop au.monster.tracker.plus
  done
}
drive_restore
; then
      echo "Emulator reconnected but did not report a completed boot." >&2
      return "$status"
    fi
    adb shell am force-stop au.monster.tracker.plus || true
    sleep 3
  done
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
adb install -r ../baseline-flutter-release/Business-Tracker-2.1.0.apk
adb shell am start -W -n au.monster.tracker.plus/au.monster.tracker.MainActivity
wait_for_ui 'Your business at a glance' flutter-2.1.0
adb exec-out screencap -p > device-evidence/baseline-flutter-2.1.0.png
adb shell am force-stop au.monster.tracker.plus
# Keep the emulator transport stable during upgrade/restore integration tests.
# Offline-first persistence is asserted by app-level integration and database tests.
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb logcat -c
adb shell am start -W -n au.monster.tracker.plus/au.monster.tracker.MainActivity
wait_for_ui 'Record sale' direct-release
for attempt in $(seq 1 5); do
  timeout 20s adb shell uiautomator dump /sdcard/business-upgrade-inventory.xml >/dev/null 2>&1 || true
  adb exec-out cat /sdcard/business-upgrade-inventory.xml > device-evidence/direct-release-inventory-ui.xml || true
  if grep -Fq 'Units on hand' device-evidence/direct-release-inventory-ui.xml; then break; fi
  adb shell input swipe 100 500 100 120 500
done
python3 - <<'CHECK'
import xml.etree.ElementTree as ET,re
root=ET.parse('device-evidence/direct-release-inventory-ui.xml').getroot()
labels=[node.get(k,'') for node in root.iter() for k in ('text','content-desc')]
assert any('Units on hand' in label for label in labels), labels
assert any(re.search(r'(?<![0-9])25(?![0-9])',label) for label in labels), labels
print('Release 2.1.0 → release 2.2.0 shows the original 25 units before any test build runs.')
CHECK
adb exec-out screencap -p > device-evidence/direct-release-upgrade.png
adb logcat -d > device-evidence/direct-release-logcat.txt
! grep -E 'FATAL EXCEPTION|Unhandled Exception' device-evidence/direct-release-logcat.txt
# Same-certificate instrumented build reads the migration already made by release.
# Flutter drive otherwise uninstalls the app during cleanup; keep it for persistence proof.
drive_checked upgrade true
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
drive_checked empty false

# Exercise the in-app restore screen against a synthetic, checksum-valid
# seven-event business backup. This clear is limited to the disposable emulator.
adb shell pm clear au.monster.tracker.plus >/dev/null
drive_restore() {
  local attempt status log
  for attempt in 1 2 3; do
    log="device-evidence/drive-restore-$attempt.log"
    set +e
    timeout 8m flutter drive --no-dds --keep-app-running --driver=test_driver/integration_test.dart --target=integration_test/restore_test.dart --dart-define-from-file=config/google-oauth.json 2>&1 | tee "$log"
    status=${PIPESTATUS[0]}
    set -e
    if [ "$status" -eq 0 ]; then return 0; fi
    if [ "$attempt" -eq 3 ] || ! grep -Fq 'Service connection disposed' "$log" || grep -Eq 'EXCEPTION CAUGHT|Test failed|Some tests failed' "$log"; then
      adb logcat -d > device-evidence/restore-failure-logcat.txt
      return "$status"
    fi
    echo "Retrying restore test attachment after a pre-test transport disconnect; emulator app data remains disposable."
    timeout 30s adb wait-for-device
    adb shell am force-stop au.monster.tracker.plus
  done
}
drive_restore
