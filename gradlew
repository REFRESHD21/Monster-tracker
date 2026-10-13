#!/bin/sh
# Source-only Gradle bootstrap. Downloads build tools, never app runtime resources.
# A binary wrapper could not be generated in the authoring environment.
set -eu
cd "$(dirname "$0")"
if command -v gradle >/dev/null 2>&1; then exec gradle "$@"; fi
cache="${GRADLE_USER_HOME:-$HOME/.gradle}/monster-bootstrap"
mkdir -p "$cache"
if [ ! -x "$cache/gradle-8.9/bin/gradle" ]; then
  for option in "$@"; do
    if [ "$option" = "--offline" ]; then
      echo 'BUILD BLOCKED: Gradle 8.9 is not installed/cached. Android SDK also needs installation; no APK was produced.' >&2
      exit 1
    fi
  done
  command -v curl >/dev/null || { echo 'Install Gradle 8.9 or curl and unzip.' >&2; exit 1; }
  curl --fail --location --connect-timeout 10 --max-time 30 --retry 1 -o "$cache/gradle-8.9-bin.zip" https://services.gradle.org/distributions/gradle-8.9-bin.zip
  curl --fail --location --connect-timeout 10 --max-time 30 --retry 1 -o "$cache/gradle-8.9-bin.zip.sha256" https://services.gradle.org/distributions/gradle-8.9-bin.zip.sha256
  expected=$(tr -d '[:space:]' < "$cache/gradle-8.9-bin.zip.sha256")
  actual=$(sha256sum "$cache/gradle-8.9-bin.zip" | cut -d ' ' -f 1)
  [ "$expected" = "$actual" ] || { echo 'Gradle checksum mismatch.' >&2; exit 1; }
  unzip -q -o "$cache/gradle-8.9-bin.zip" -d "$cache"
fi
exec "$cache/gradle-8.9/bin/gradle" "$@"
