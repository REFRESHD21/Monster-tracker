# Install the verified Android app

The existing Monster Tracker Plus project was built and tested in [successful run 38409682236](https://github.com/REFRESHD21/Monster-tracker/actions/runs/38409682236). It ran 111 host checks, 19 fake-provider backend tests, Android unit tests, and 45 Android checks in airplane mode. `assembleDebug` and `assembleRelease` succeeded. The primary APK's ZIP structure, DEX, launcher, version, package and signing certificate were verified.

## Install from your phone

1. Export your current app's full backup first. Do not uninstall it to resolve an installation/signing error.
2. Open the successful run above in Chrome, sign into GitHub, and download **monster-tracker-apk** from **Artifacts**.
3. Extract the artifact ZIP in Android Files/My Files. Tap **Monster-Tracker-1.6.1.apk**.
4. Allow **Install unknown apps** for Files/My Files when prompted, then install. Open **Monster Tracker Plus** from your app drawer; long-press its icon to add it to the home screen if necessary.
5. Existing Plus data migrates in place when the signing certificate matches. If moving from the original separate Monster Tracker app, keep that app installed and import its full backup into Plus. Matching opening IDs do not double stock.

Android 8.0+ supports the tracker. Sales recorded manually/cash, purchases, receipts, OCR, saved barcodes, stock, shopping lists, reports and backups work offline. Stripe processing/status requires connectivity and owner setup; supported Tap to Pay devices require Android 13+ and Stripe's other conditions. Nothing requires Android Studio on the phone.

The artifact also contains `SHA256SUMS.txt`, `apk-verification.txt`, and `INSTALL.txt`. **monster-tracker-debug-apk** is a separate development APK; use the primary non-debuggable APK for normal installation and Stripe testing. **monster-tracker-build-reports** contains logs and verification results. These artifacts expire on 2026-11-12; the installed app does not expire.

## Take a live receipt photo

Open **Stock → Supplier purchases, receipts & expenses → New supplier purchase** (or operating expense). Tap **Take live receipt photo**, allow camera access, tap the preview to focus, then capture. **Preview attached photo** lets you check it. **Read attached receipt with offline OCR** produces draft suggestions; review/edit every line before confirming the document. Saving the document does not add stock. Confirm only goods actually received, separately, with the actual quantity.

History also supports live receipt photos on existing records. The opening 24-can/$50 purchase is already counted; attaching its photo in History does not restock it again. The four opening missing cans retain an unknown date and are not sales.

## Back up and restore

Use **Settings → Encrypted backups, automatic schedule & recovery → Export portable encrypted backup**. Confirm a password and choose a local/USB/provider destination. The app reads and decrypts the written file to validate it. Keep both the file and password outside this phone. On a replacement phone, install the app, choose **Restore encrypted backup**, select the file, enter its original password, review the merge/settings preview and confirm.

Schedules default off. Set an automatic-backup password, optionally choose a folder, enable daily/weekly scheduling, and use **Back up now** to verify the first copy. The latest seven verified app-private copies are available through **View local recovery copies**; uninstall/clear-data/phone loss removes them. Android may delay background jobs. Provider/cloud delivery depends on the selected provider and is not a verified remote-cloud service. Plain JSON and CSV options remain available. Full JSON is limited to 64 MB and individual original receipts to 16 MB; oversize exports fail visibly without altering live records.

Full backups finalize an already saved local queue exactly once. Pending Stripe checkouts, pairing tokens and scheduled-backup secrets are intentionally excluded. Resolve pending card payments before phone transfer and retain the payment backend's persistent database. Changing a backup password affects new files only; older copies need their original password.

## Rebuild from your phone

In the existing repository, open **Actions → Build Monster Tracker APK → Run workflow**. Select **codex/phase-1-purchases-audit** until its changes are merged, and leave emulator tests enabled. Download artifacts only from a green run. JDK 17, Gradle 8.9 and Android SDK/build tools 35 are installed by the workflow; GitHub is not needed to operate the installed tracker.

## Production signing

Current artifacts use the explicitly cached Plus test signing key. This is not a durable privately owned production keystore. The cache can be evicted; a certificate mismatch must not be bypassed by uninstalling without a verified backup.

On a trusted computer or private CI environment with JDK 17, create and privately back up an owned key:

```sh
keytool -genkeypair -keystore monster-release.jks -alias monster -keyalg RSA -keysize 3072 -validity 10000
```

Let keytool prompt for passwords. Do not commit the keystore/passwords or put them in chat. To build a release, privately provide these environment variables to Gradle:

- `MONSTER_KEYSTORE`: absolute path to that keystore.
- `MONSTER_STORE_PASSWORD`: its store password.
- `MONSTER_KEY_ALIAS`: `monster`.
- `MONSTER_KEY_PASSWORD`: its key password.

Then run `gradle :app:assembleRelease`. The existing Gradle configuration uses that owned key when provided. For GitHub CI, keep encrypted keystore material and passwords in repository **Actions secrets**, decode the file into a private runner temporary path in a trusted manual workflow, and set the same environment variables for the Gradle step. Do not expose production signing secrets to pull-request builds. A changed certificate cannot update an existing installation directly; plan and verify record migration while preserving the old app/data first.

No owned production key, actual Stripe API test transaction, deployed payment backend or physical Tap to Pay charge was configured here. [STRIPE_SETUP.md](STRIPE_SETUP.md) lists the exact owner account, test credentials, persistent HTTPS backend and device steps. Physical receipt capture quality, barcode framing, provider/cloud delivery and real background timing also need phone verification. Disputes/chargebacks and webhook-driven refund reconciliation are not automated.
