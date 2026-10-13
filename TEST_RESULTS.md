36 host checks passed: 26 production Java ledger/backup tests, nine real host SQLite schema tests, and one parity check covering 100 original/native scenarios.

The production core Java code compiled successfully. See reports/host-tests.txt for actual output.

Not run: nine Android instrumentation tests, Android UI/database integration, Gradle compilation, APK signature/manifest verification, emulator/device/airplane-mode installation checks.

No APK was generated. The Android build attempt stopped at missing Gradle/SDK before compiling the Android code. See reports/android-build-attempt.txt.

GitHub Actions fallback added: JDK 17, Gradle 8.9 and Android SDK 35 setup; actual testDebugUnitTest/assembleDebug/assembleDebugAndroidTest tasks; optional-by-dispatch emulator tests enabled by default; signature/package/DEX/zero-permission verification; APK artifact upload only after success. YAML and embedded shell syntax validated locally. Workflow not executed; no Android/Gradle test result or APK success is claimed.
