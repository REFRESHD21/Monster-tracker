# Monster Tracker 1.1

Installs as **Monster Tracker Plus** alongside the original app. Export a JSON backup from the original, then import it into Plus to transfer your records safely.

A native Android stock and sales ledger with local receipt photos and optional Stripe Tap to Pay.

- Cash and manual card entries, stock purchases/adjustments, history and JSON backups work offline.
- Optional Google Sheets uploads: manual Upload now, automatic network-constrained retries, duplicate protection and sync status. Configure your own private spreadsheet receiver using [SHEETS_SETUP.md](SHEETS_SETUP.md). This does not require Stripe.
- Attach receipt photos through History > transaction > Receipt photos. Images are copied into the app and included in full JSON backups; CSV contains transaction data only.
- Stripe Terminal 6.0.0 provides native Tap to Pay. A merchant-owned Stripe account and authenticated HTTPS payment backend are required. The included `backend/` uses durable SQLite and idempotent PaymentIntents. Test payments do not modify stock or revenue.
- Real payments require a compatible physical Android 13+ phone. Samsung Galaxy A16 5G is on Stripe's device list; actual compatibility depends on NFC, security updates and device settings.
- Version 1 databases upgrade without clearing existing history. Version 1 JSON backups remain readable.

See [STRIPE_SETUP.md](STRIPE_SETUP.md) for installation, receipt backups, account/backend setup and recovery. No live account, backend deployment or physical Tap to Pay charge has been configured here.

## Build

GitHub Actions runs host accounting/backup checks, payment-backend tests, Android unit tests, database/receipt/migration tests in an offline emulator, and APK package/signature/manifest verification. It exports a non-debuggable `Monster-Tracker-1.1.apk`.

Locally with JDK 17, Android SDK and Gradle 8.9:

```sh
./gradlew :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest :app:assembleRelease
bash scripts/verify-apk.sh app/build/outputs/apk/release/app-release.apk
```

The release build uses a new, explicitly cached signing key for Plus; the original workflow did not retain its key. Configure `MONSTER_KEYSTORE`, `MONSTER_STORE_PASSWORD`, `MONSTER_KEY_ALIAS` and `MONSTER_KEY_PASSWORD` privately to use your own production key; changing keys requires a planned record migration.

## Ledger behavior

Opening inventory is 24 cans purchased for AUD $50, with four missing and unknown historical dates: 20 available, $0 revenue, −$50 cash result. Singles default to $3.50 and two-can deals to $6. Prices and actual card fees are retained per sale. Cash result is revenue minus actual card fees minus all purchase costs, rather than cash drawer balance.

Transaction history is append-only. Normal corrections add undo events; Stripe-paid sales cannot be undone because a ledger correction does not refund money. Stripe refunds/chargebacks require separate Dashboard handling and reconciliation in this version. Pending Stripe payments block new entries until resolved so retries reuse the same payment and stock allocation.

Receipts and records remain private on the phone. Backups are unencrypted and should be kept in a safe separate location. Stripe pairing credentials are encrypted in Android Keystore and excluded from backups. Never put Stripe secret keys in the APK or GitHub.

The original pre-Android ledger and README are preserved under `provenance/`. Earlier build reports in `reports/` describe the source conversion; current CI reports are available as workflow artifacts.
