#!/bin/sh
set -eu

echo 'Waiting up to 3 minutes for the Android device...'
timeout 180 adb wait-for-device
boot_deadline=$(($(date +%s) + 180))
while [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != '1' ]; do
  now=$(date +%s)
  if [ "$now" -ge "$boot_deadline" ]; then
    echo 'Emulator did not finish booting within 3 minutes.' >&2
    adb devices -l || true
    adb logcat -d -t 200 || true
    exit 1
  fi
  sleep 5
done

echo 'Emulator boot completed.'
baseline="$(find upgrade-baseline -name '*.apk' -type f | head -n 1)"
test -n "$baseline"
timeout 120 adb install "$baseline"
timeout 60 adb shell am start -W -n au.monster.tracker.plus/au.monster.tracker.MainActivity
sleep 3
timeout 30 adb shell am force-stop au.monster.tracker.plus
timeout 120 adb install -r universal/build/app/outputs/flutter-apk/app-debug.apk
adb logcat -c
timeout 60 adb shell am start -W -n au.monster.tracker.plus/au.monster.tracker.MainActivity
sleep 8
adb shell pidof au.monster.tracker.plus
adb shell run-as au.monster.tracker.plus test -s databases/business-tracker-v1.db
if adb logcat -d | grep -E 'FATAL EXCEPTION|MIGRATION_BLOCKED'; then
  echo 'App crash or migration blocker detected during emulator smoke test.' >&2
  exit 1
fi

echo 'Existing-install upgrade, startup, and database smoke test passed.'
