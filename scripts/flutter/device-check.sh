#!/usr/bin/env bash
set -euo pipefail
mkdir -p device-evidence/before
adb install ../baseline-debug/app-debug.apk
adb shell am start -W -n au.monster.tracker.plus/au.monster.tracker.MainActivity
sleep 4
adb shell am force-stop au.monster.tracker.plus
adb exec-out run-as au.monster.tracker.plus tar -cf - databases | tar -xf - -C device-evidence/before
python3 ../scripts/flutter/seed-upgrade.py device-evidence/before/databases/monster-offline.db
adb push device-evidence/before/databases/monster-offline.db /data/local/tmp/legacy-upgrade.db
adb shell run-as au.monster.tracker.plus rm -f databases/monster-offline.db-wal databases/monster-offline.db-shm
adb shell run-as au.monster.tracker.plus cp /data/local/tmp/legacy-upgrade.db databases/monster-offline.db
adb shell cmd connectivity airplane-mode enable
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/upgrade_test.dart --dart-define=EXPECT_LEGACY=true
# Prove the uninstrumented release APK also updates in place and launches.
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb logcat -c
adb shell am start -W -n au.monster.tracker.plus/au.monster.tracker.MainActivity
sleep 5
adb exec-out screencap -p > device-evidence/release-upgrade.png
adb logcat -d > device-evidence/release-logcat.txt
! grep -E 'FATAL EXCEPTION|Unhandled Exception' device-evidence/release-logcat.txt
# Fresh-install path has no old database and must remain empty.
# This clear is on the disposable CI emulator only, after the upgrade proof.
adb shell pm clear au.monster.tracker.plus
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/upgrade_test.dart --dart-define=EXPECT_LEGACY=false
