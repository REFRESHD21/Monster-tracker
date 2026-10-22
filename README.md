# Universal Business Tracker — Flutter rebuild

The shared Android/iPhone application lives in [universal/](universal/README.md).
It starts from the complete 1.6.3 source, retains Android package
`au.monster.tracker.plus`, and introduces version 2.0.0 (11). Use the
**Universal tracker** workflow and its verified Android update artifact.
The original Java application below remains the migration/accounting reference.
The Flutter app has no Tap to Pay or store-publication workflow.

See [migration, signing and iPhone setup](universal/README.md) and the
[privacy-policy draft](universal/PRIVACY_DRAFT.md). Do not uninstall your current
app to resolve an update error; export a full backup before installing.

---

# Monster Tracker 1.6.3

Installs as **Monster Tracker Plus** alongside the original app. Export a JSON backup from the original, then import it into Plus to transfer your records safely.

A native Android stock and sales ledger with local receipt photos and optional Stripe Tap to Pay.

- Optional manual/automatic Google Sheets sales-and-stock uploads; see [SHEETS_SETUP.md](SHEETS_SETUP.md). Supplier documents, refunds and financial reports remain in their existing offline tools and backups.
- Cash and manual card entries, stock purchases/adjustments, history and JSON backups work offline.
- Take live receipt photos or import them through History > transaction > Receipt photos. Images are copied into the app and included in full JSON backups; CSV contains transaction data only.
- Stripe Terminal 6.0.0 provides native Tap to Pay. A merchant-owned Stripe account and authenticated HTTPS payment backend are required. The included `backend/` uses durable SQLite and idempotent PaymentIntents. Test payments do not modify stock or revenue.
- Real payments require a compatible physical Android 13+ phone. Samsung Galaxy A16 5G is on Stripe's device list; actual compatibility depends on NFC, security updates and device settings.
- Version 1/2/3 databases migrate safely to version 6. Legacy JSON backups remain readable.
- Stock > Supplier purchases supports reviewed multipacks, expenses and original JPG/PNG/PDF receipts with bundled offline OCR. Confirm invoices first, then confirm actual goods received separately; partial deliveries are supported.
- Home/Settings > Profit reports supports offline FIFO COGS, profit by flavour, daily through annual reports, GST settings (default unregistered), and CSV/PDF export. Historical prices and GST snapshots remain unchanged by settings changes.
- Stock > Flavours supports offline barcode assignments, per-flavour stock counts, minimum/target alerts, preferred suppliers and shopping lists. Current legacy stock remains explicitly unassigned until you identify its flavour with an audited stock transfer.

See [STRIPE_SETUP.md](STRIPE_SETUP.md) for installation, receipt backups, account/backend setup and recovery. No live account, backend deployment or physical Tap to Pay charge has been configured here.

## Build

GitHub Actions runs host accounting/backup checks, payment-backend tests, Android unit tests, database/receipt/migration tests in an offline emulator, and APK package/signature/manifest verification. It exports a non-debuggable `Monster-Tracker-1.6.3.apk`.

Locally with JDK 17, Android SDK and Gradle 8.9:

```sh
./gradlew :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest :app:assembleRelease
bash scripts/verify-apk.sh app/build/outputs/apk/release/app-release.apk
```

The release build uses a new, explicitly cached signing key for Plus; the original workflow did not retain its key. Configure `MONSTER_KEYSTORE`, `MONSTER_STORE_PASSWORD`, `MONSTER_KEY_ALIAS` and `MONSTER_KEY_PASSWORD` privately to use your own production key; changing keys requires a planned record migration.

## Ledger behavior

Opening inventory is 24 cans purchased for AUD $50, with four missing and unknown historical dates: 20 available, $0 revenue, −$50 cash result. Singles default to $3.50 and two-can deals to $6. Prices and actual card fees are retained per sale. Cash result is revenue minus actual card fees minus all purchase costs, rather than cash drawer balance.

Transaction history is append-only. Normal corrections add undo events; Stripe-paid sales cannot be undone because a ledger correction does not refund money. History > sale > Refunds & returned goods supports source-linked manual/Stripe refunds and verified Dashboard-refund reconciliation. Chargebacks/disputes still require separate Stripe handling and are not automatically reconciled. Pending Stripe payments block new entries until resolved so retries reuse the same payment and stock allocation.

Receipts and records remain private on the phone. Ordinary JSON backups are unencrypted; encrypted portable backups and scheduled recovery copies are available in Settings > Encrypted backups. Keep the password and a file outside the phone. Stripe pairing credentials are encrypted in Android Keystore and excluded from backups. Never put Stripe secret keys in the APK or GitHub.

The original pre-Android ledger and README are preserved under `provenance/`. Earlier build reports in `reports/` describe the source conversion; current CI reports are available as workflow artifacts.

## Live receipt photos

In **Stock → Supplier purchases, receipts & expenses → New supplier purchase** (or **Record operating expense**), tap **Take live receipt photo**. Allow camera access, point the rear camera at the whole receipt, tap to focus, and tap **Take receipt photo**. Tap **Preview attached photo** to check it, or capture again to replace the unsaved attachment. Tap **Read attached receipt with offline OCR**, review the suggestions, and correct supplier/date, quantities, flavours, costs and GST before **Confirm document**. Saving a receipt never confirms delivery or adds stock automatically.

After the goods arrive, open the saved purchase and use **Confirm received goods** with the actual received quantity. The original image remains in private SQLite and is included in the full JSON backup. Barcode/OCR models are bundled with the APK and need no download on first use. Actual camera quality, focus and retail scanning need verification on your phone; see [PHASES.md](PHASES.md) for current build/test status.

To update, export a full JSON backup first, then install the new APK over the existing **Monster Tracker Plus** using the same signing key. Do not uninstall Plus to resolve an installation error: uninstalling erases its database. If signing keys differ, keep the old installation and backup while arranging migration. Backup files do not survive phone loss unless copied elsewhere.

## Encrypted backup and replacement-phone recovery

Open **Settings → Encrypted backups, automatic schedule & recovery**. **Export portable encrypted backup** asks you to enter the same password twice and choose a file destination. Use at least 10 characters and keep that password somewhere safe outside the phone. The app verifies the file by reading/decrypting it after writing. On another Android phone, install the app and choose **Restore encrypted backup**, select the `.monsterbackup` file, enter its original password, review the preview and confirm **Merge & restore**. Matching opening/event IDs do not double stock; conflicting records reject the restore.

For automatic copies, set an automatic-backup password, optionally choose a local/removable/provider folder, enable daily/weekly scheduling and tap **Back up now** to verify a real copy. Android may delay background jobs. The latest seven verified app-private copies can be opened through **View local recovery copies**; those copies are lost on uninstall/clear-data/phone loss. Provider/cloud copies require the provider to function and sync; verify them yourself before relying on remote storage. Password changes only affect new backups; keep previous passwords for older files. Stripe pairing and schedule credentials must be reconfigured after changing phones.

## Refunds and payment recovery

Open **History → sale → Refunds & returned goods**. Record a cash/manual-card refund already paid, or request a Stripe refund through the original live backend. Refund requests are saved before submission and keep the same ID for retries. Check/retry the existing request after an interruption; do not create another request. **Reconcile Stripe status & Dashboard refunds** retrieves provider status without charging a customer. Pending/failed/canceled refunds stay visible. The original fee is retained; any additional refund fee is recorded only when known. Cash/manual refunds require no internet.

Use **Confirm physically received returned cans** only after you actually receive them. Their original FIFO cost is restored; a refund alone never adds inventory. Financial report CSV/PDF includes refund money/fees, later failures and goods returns. The ordinary sales/stock CSV keeps the original sale records.

After a successful Stripe test/simulated payment, the payment screen offers **Test refund / check same test refund**. Test payments/refunds never change the real ledger. Actual Stripe credentials and physical-device verification are still required. Pending live payments are automatically checked when connectivity returns; actual settlement fees must be known before finalizing the sale, so its cans remain reserved until the fee is known; other available cans can still be sold for cash/manual payments offline. See [STRIPE_SETUP.md](STRIPE_SETUP.md) for exact owner setup and [PHASES.md](PHASES.md) for completed versus externally unverified checks.

A pending payment reserves only its flavour/quantity. Available-stock displays and shopping alerts exclude that reservation; other cash/manual entries can continue offline. Resolve that flavour's payment before a physical count, and resolve all pending payments before phone transfer. Manual refund dates can explicitly stay unknown; incorrect manual refund records have append-only corrections. A physical return is independent of refund status and always needs your explicit confirmation.

## Previous verified download

The current 1.6.1 application passed all 111 host checks, 19 fake-provider backend tests, Android unit tests and 45 airplane-mode Android checks in [run 38409682236](https://github.com/REFRESHD21/Monster-tracker/actions/runs/38409682236). Download **monster-tracker-apk** for phone installation. A separate debug APK is available. [GITHUB_BUILD.md](GITHUB_BUILD.md) has current installation, backup/recovery, signing and phone-friendly rebuild instructions. Actual physical-camera/Stripe/cloud-provider verification remains external; no real Stripe API write/readback is claimed.
