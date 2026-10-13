# Monster Tracker 1.1 — Stripe Tap to Pay and receipt photos

See [STRIPE_SETUP.md](STRIPE_SETUP.md) for installation, local receipt backups, Stripe account/backend setup, device requirements and payment recovery. Cash/manual records still work offline; Stripe payments require internet. This revision adds network/location permissions. Older zero-permission and unbuilt-APK statements below describe version 1.0 and are retained for provenance only.

# Monster Tracker — native offline Android conversion

**Build from your phone:** see [GITHUB_BUILD.md](GITHUB_BUILD.md). A GitHub Actions workflow now builds this existing app, runs host/Android unit tests and optional emulator tests, verifies the debug APK, and uploads it as an artifact. No Android Studio is needed on your phone. The workflow has not yet run.

**Deliverable status:** native Android source implemented; 36 host checks passed again. **No APK was built here.** Gradle, the Android SDK, `adb` and an emulator are unavailable in the authoring environment. Android download requests did not execute. The Android UI/database classes have not been compiled against an Android SDK or tested on a device. This project is not yet an installation-ready deliverable.

The ZIP and original README were inspected before conversion. This is a port of the existing Monster Tracker's ledger, not a server wrapper. The original ledger and README are preserved under `provenance/` for comparison. None of that directory is packaged into the Android app. OAuth, Google Sheets, Node, service workers, browser storage, GitHub, Render, and servers have no role in the app runtime.

## Architecture

Native Java 17 Android screens and Android's built-in `SQLiteOpenHelper`/SQLite API were chosen instead of Kotlin/Compose/Room to keep the application free of third-party runtime libraries and permit the production ledger/backup logic to be tested independently of an Android toolchain. There is no WebView, remote font, downloaded interface or network API. The manifest requests **zero permissions**, including no INTERNET permission. All runtime resources ship in the APK when it is built.

- `Ledger.java`: direct port of the old ledger, with integer-cent accounting, protected stock and traceable undo. The native totals matched the original JavaScript ledger in 100 automated scenarios.
- `Store.java`: local database, one-time opening seed, WAL, foreign keys, unique IDs, transactional writes and settings. SQL triggers forbid rewriting or deleting transaction history.
- `Backup.java` / `Json.java`: full versioned JSON backups, SHA-256 integrity checks, strict validation and CSV. Backup restore merges without deleting current data.
- `MainActivity.java`: five native tabs: dashboard, sale, stock, history and settings. File access uses Android's local document picker without broad storage permission.

Android 8.0/API 26 or later is targeted as the minimum. The project compiles against SDK 35 and targets SDK 35. Runtime compatibility remains unverified until an Android build and device test are completed.

## Opening inventory

The database's first creation seeds exactly these two immutable IDs inside SQLiteOpenHelper's creation transaction:

| ID | Event | Quantity | Cost | Historical timestamp |
|---|---|---:|---:|---|
| `opening-purchase-v1` | Original stock purchase | 24 | AUD $50.00 | Unknown |
| `opening-missing-v1` | Existing opening missing adjustment | 4 | $0.00 | Unknown |

Starting availability is 20, revenue $0, and cash result −$50. Opening events never acquire invented historical dates. Their separate `recordedAt` metadata reflects when the Android database was initialized, not when the purchase/loss happened. Seeding only runs on database creation, not each launch. No migration drops or resets the database.

No user transaction database or exported records were included in the original source ZIP, so only the verified historical opening records are available to seed. The new JSON format is for this Android app; old PWA export files are not silently interpreted as native backups.

## Business behavior

- Singles default to $3.50 and remove one can. Deals default to $6.00 and remove two cans.
- Choose cash/card, the sale's actual date/time in Perth, actual card fee, and an optional note. The fee must be zero for cash and cannot exceed sale revenue. Card is a recording category, not payment processing.
- Each sale retains its price and fee. Settings change future defaults only.
- Stock purchases add quantity and purchase cost. Missing, damaged and lost cans remove stock without revenue. Current inventory and totals update from the immutable ledger.
- Cash result is all revenue − actual fees − all stock purchase costs; it is not cash drawer balance or profit allocated only to sold cans.
- Undo appends a new record referencing an original ID. To change an incorrect sale, undo and enter the corrected sale. You cannot undo twice, undo an undo, or undo a purchase when that would make stock negative.
- A confirmation stages a durable command before committing it. If the process stops before or after the transaction commits, recovery retries the same ID rather than creating another transaction. Repeated taps are disabled while saving; the sale screen closes after a successful save.
- Event times and recorded-on-device times are stored as epoch milliseconds, exported as UTC ISO timestamps, and displayed in Australia/Perth. Unknown opening times remain null.
- The app has a protective 10,000-record limit and a 64 MB backup-file limit. Hitting a limit reports an error and preserves existing data; it never silently deletes or rotates history.

## Build the actual APK

These steps still need to be completed in an Android-capable build environment. Development tool downloads can need internet; the resulting app does not.

1. Install Android Studio with its bundled JDK 17 or later. In SDK Manager install **Android SDK Platform 35**, **Build Tools 35.0.0** and Platform Tools. An emulator is optional if using a physical phone.
2. Extract this project. Set `ANDROID_HOME` to the SDK path or create `local.properties` with `sdk.dir=/absolute/path/to/android-sdk`. Never put that machine-specific file in source control.
3. Install Gradle 8.9, or run the provided bootstrap script from a terminal:

   ```sh
   chmod +x gradlew
   ./gradlew :app:assembleDebug :app:assembleDebugAndroidTest
   ```

   Windows: `gradlew.bat :app:assembleDebug :app:assembleDebugAndroidTest`.

   A standard binary wrapper could not be generated here. The source-only bootstrap downloads the official Gradle distribution and checks its published SHA-256. To generate a conventional wrapper for Android Studio, run `./gradlew wrapper --gradle-version 8.9` once, then open the project root in Android Studio and sync. If using an installed Gradle, verify it is 8.9 or a compatible version.
4. The debug APK, if the build succeeds, will be:

   ```text
   app/build/outputs/apk/debug/app-debug.apk
   ```

5. Verify its signature and manifest with `ANDROID_HOME` set:

   ```sh
   ./scripts/verify-apk.sh
   ```

   This script must pass before claiming the APK is verified. It has **not** run successfully here because no APK/build tools exist.
6. Run the included Android database tests on a connected device/emulator:

   ```sh
   ./gradlew :app:connectedDebugAndroidTest
   ```

   Or install the app and test APKs and run the custom instrumentation runner:

   ```sh
   adb install -r app/build/outputs/apk/debug/app-debug.apk
   adb install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
   adb shell am instrument -w au.monster.tracker.test/au.monster.tracker.DatabaseTestRunner
   ```

   Device tests use isolated test databases and do not clear the business database. There are nine device tests; none have been run here. The Actions workflow runs them by default on an emulator in airplane mode.

## Android installation — after an APK is built

1. Copy `app-debug.apk` to the phone by USB, Bluetooth, an SD card or another local transfer method.
2. Open it in Android Files. If prompted, permit **Install unknown apps** for that Files app, then tap **Install**.
3. Launch **Monster Tracker** from the M icon. No sign-in, setup URL or network connection should be required.
4. To verify first launch, enable airplane mode **before launching it for the first time**. Check 20 cans, four missing, $50 purchases, $0 revenue and −$50 cash result. Record a testing-only sale and undo it. Force-stop and reopen; confirm the records and totals persist.
5. Export a JSON backup, transfer it locally to a second test device, restore it, and verify the same IDs and totals.

These are acceptance instructions, not a claim that an APK or real-device test is complete.

## Backup, restore and replacement phones

**Export:** Settings → Export full JSON backup → choose a local folder such as Downloads → Save. Keep a copy on a USB drive, SD card, computer or another phone. The file includes all events, undo references, opening records and default prices. It is not encrypted; keep it private.

**Restore:** transfer the JSON file to the replacement phone, install the app, then Settings → Import / restore JSON backup → select the local file. The app validates the file, checksum, format, prices, event IDs, opening records, dates, quantities, payments, fees, correction references and stock availability before presenting a confirmation.

The confirmation shows how many records will be added and which default prices will be applied. Existing records remain. Matching IDs are skipped, so restoring the same backup twice does not duplicate data. Conflicting IDs or incompatible stock histories reject the entire import transaction; neither events nor prices are changed. This is a **merge restore**, not a destructive replacement/reset.

**CSV:** Settings → Export transaction history CSV. CSV contains IDs, UTC/Perth times, amounts, notes and correction references. Unknown dates export as blank. Note cells beginning with spreadsheet formula characters receive a leading apostrophe in CSV; the stored note and JSON backup are unchanged. CSV is not a restore format.

**Uninstall/clear-data/reset/phone loss:** the local database can be erased. Do not assume it survives uninstalling. Export before uninstalling, clearing storage, switching APK signing keys or replacing the phone. Automatic Android cloud/device-transfer backup is disabled; the explicit JSON file is the supported transfer path. A backup stored only on the lost phone is not a useful recovery copy.

## Signed release APK and updates

The debug APK is for installation/testing. For a release, in Android Studio choose **Build → Generate Signed App Bundle / APK → APK**, create or select a keystore, and build the release variant. Keep the same application ID and signing key for future updates. Back up the private keystore and its passwords securely, outside the project; never commit them.

CLI release signing is also supported through these environment variables:

- `MONSTER_KEYSTORE`: absolute path to your keystore
- `MONSTER_STORE_PASSWORD`
- `MONSTER_KEY_ALIAS`
- `MONSTER_KEY_PASSWORD`

Then run `./gradlew :app:assembleRelease`. Without signing variables, that variant is unsigned; do not describe it as installable. Increment `versionCode` for updates. Normal updates signed with the same key retain the database. Switching from a debug APK to a release with a different signing key requires backing up first, uninstalling, installing the release and importing the JSON backup.

## Tests and verified limits

Run locally with a JDK 17+ and Python 3:

```sh
./scripts/test-core.sh
```

Node is optional for the extra original-ledger parity check. The script uses the JDK compiler module so it can run even when a separate `javac` launcher is absent.

**Actually run:**

- 26 checks compile and execute the production Java ledger, JSON and backup code.
- Nine Python host tests run the exact production SQLite schema against real file-backed SQLite: one-time openings, persistence, duplicates, rollback, immutable history, correction constraints, restore, pending-command recovery and the no-permission manifest.
- One parity check compares the native ledger with the uploaded original ledger across 100 business scenarios.

All **36 host checks passed**. See `reports/host-tests.txt`.

**Not verified:** Android Gradle build, actual APK, native Activity/SQLiteOpenHelper execution, document-picker behavior, icon/installation, emulator or real-device first launch/restart in airplane mode. The nine Android instrumentation tests are supplied but unrun. Host SQLite tests are not a substitute for Android database tests. The recorded build attempt stopped before compilation because Gradle/SDK were missing; see `reports/android-build-attempt.txt`.

The final requested APK deliverable therefore remains incomplete. No `.apk` is included or claimed.
