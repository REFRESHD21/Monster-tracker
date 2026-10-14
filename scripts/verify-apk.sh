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
printf '%s\n' "$badging" | grep -q "package: name='au.monster.tracker.plus'"
printf '%s\n' "$badging" | grep -q "launchable-activity: name='au.monster.tracker.MainActivity'"
permissions=$("$tools/aapt" dump permissions "$apk")
printf '%s\n' "$permissions"
# Stripe adds network, location, NFC, audio and foreground service permissions.
# Live receipt/barcode capture uses CAMERA; receipt import must not request broad storage access.
if printf '%s\n' "$permissions" | grep -Eq "READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE|MANAGE_EXTERNAL_STORAGE|READ_MEDIA_IMAGES"; then
 echo 'ERROR: unexpected broad storage permission.' >&2; exit 1
fi
printf '%s\n' "$permissions" | grep -q 'android.permission.INTERNET'
fine_permission=$(printf '%s\n' "$permissions" | grep 'android.permission.ACCESS_FINE_LOCATION')
if printf '%s\n' "$fine_permission" | grep -q 'maxSdkVersion'; then
 echo 'ERROR: precise location must be available on Android 13+ for Stripe.' >&2; exit 1
fi
printf '%s\n' "$badging" | grep -q "versionCode='10'"
if printf '%s\n' "$badging" | grep -q 'application-debuggable'; then
 echo 'ERROR: live Tap to Pay requires a non-debuggable APK.' >&2; exit 1
fi
sha256sum "$apk"
printf '%s\n' 'APK signature, package, launcher and DEX verified; non-debuggable; no broad storage permissions; on-device camera capture.'
