# GitHub Release draft — Business Tracker 2.3.1

**State:** copy-ready draft only. Do not publish until the release signer is durable and the real-backup restore gate is complete.

## Proposed metadata

- **Release title:** Business Tracker 2.3.1 (Android APK)
- **Tag:** `v2.3.1`
- **Target:** `feature/flutter-universal-tracker` (replace with the approved release commit/tag before publishing)
- **Package:** `au.monster.tracker.plus`
- **Version:** 2.3.1 (version code 18)
- **Assets:** [Verified APK artifact from Actions run #68](https://github.com/REFRESHD21/Monster-tracker/actions/runs/38855799857/artifacts/12027279807), containing `Business-Tracker-2.3.1.apk` and `SHA256SUMS.txt`.
- **Signing fingerprint:** `10195e6471ae52ad19633421aa4e50db9bf391fbbb15eb58016c41a6eef1c2dd` is the current CI compatibility certificate. It is not yet backed by an owner-controlled durable release key.

## Release notes draft

Business Tracker keeps product, sales, purchases, stock movements, expenses and reports on your device. It works offline and includes FIFO stock costing, stocktake, and full backup export and restore.

This app records cash/card labels for bookkeeping; it does not charge payment cards. Google Sheets is optional and uploads one-way only when you connect it.

### Install or update

1. Download `Business-Tracker-2.3.1.apk` and `SHA256SUMS.txt` from this release.
2. Verify the APK SHA-256 against `SHA256SUMS.txt` before installing.
3. Open the APK on Android and approve installation for the browser or file manager if prompted.
4. For an update, keep the existing app installed and install over it. Android permits this only when the package ID and signing identity match. The package ID remains `au.monster.tracker.plus`.
5. If Android reports a signature conflict or the update is refused, cancel. Do not uninstall or clear app data. Export a backup first and contact support.

### Back up and restore

Before an update or device change, open **Settings → Backups & recovery → Export encrypted full backup**. Save the file somewhere outside the phone and keep its password separately. Full JSON backup is available but is not encrypted.

To restore, install the app, open **Settings → Import / restore backup**, choose the backup, check the business name, product/event counts and totals in the preview, then confirm. Restore into an empty installation for a full restore; existing history is never silently overwritten. Keep the source backup until the restored stock, purchases, sales and reports have been checked.

### Important

- No Google Play listing or automatic update is included with this GitHub APK. Future GitHub releases must be installed manually.
- Never uninstall or clear the existing app as a troubleshooting step before verifying an off-device backup.
- The certificate listed above matches the CI compatibility APK tested in GitHub Actions. A durable owner-controlled copy and final real-backup restore test are prerequisites to publishing this release.

## Verification record to fill after the final CI run

- CI run: [#68 — all jobs passed](https://github.com/REFRESHD21/Monster-tracker/actions/runs/38855799857)
- App source commit: `442d6438174d99741d5f960d23224d1cf77ff66b`
- APK SHA-256: `c54a3dda35f2726a32d502c51cd7498e8a4e5c57cd818629e4c0303d816876cd`
- Emulator restore test: **passed** on the Android emulator using a synthetic, checksum-valid seven-event ledger. UI preview, confirmed restore, tamper rejection, archived product view and persistence after reopen passed.
- Real owner backup restore: **not tested**; the actual backup was not available to this run.
