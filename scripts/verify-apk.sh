#!/bin/sh
set -eu
apk="${1:-app/build/outputs/apk/debug/app-debug.apk}"
: "${ANDROID_HOME:?Set ANDROID_HOME to the Android SDK}"
tools="$ANDROID_HOME/build-tools/35.0.0"
[ -s "$apk" ] || { echo 'ERROR: APK absent or empty.' >&2; exit 1; }
unzip -tq "$apk"
unzip -Z1 "$apk" | grep -qx 'AndroidManifest.xml'
unzip -Z1 "$apk" | grep -qx 'classes.dex'
"$tools/apksigner" verify --verbose --print-certs "$apk"
badging=$("$tools/aapt" dump badging "$apk")
printf '%s\n' "$badging"
printf '%s\n' "$badging" | grep -q "package: name='au.monster.tracker'"
printf '%s\n' "$badging" | grep -q "launchable-activity: name='au.monster.tracker.MainActivity'"
permissions=$("$tools/aapt" dump permissions "$apk")
printf '%s\n' "$permissions"
if printf '%s\n' "$permissions" | grep -q 'uses-permission'; then
 echo 'ERROR: unexpected runtime permission in merged APK manifest.' >&2; exit 1
fi
sha256sum "$apk"
printf '%s\n' 'APK signature, package, launcher and DEX verified; zero runtime permissions.'
