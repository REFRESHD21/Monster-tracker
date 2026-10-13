# Stripe Tap to Pay and local receipt photos — version 1.6

## Install without losing your existing records

This build installs as **Monster Tracker Plus**, alongside the original Monster Tracker. The original build workflow did not retain its signing key (the cache path did not exist), so a safe in-place upgrade with the original certificate is unavailable.

1. In the old app, export a full JSON backup to your phone.
2. Install Monster-Tracker-1.6.1.apk and open **Monster Tracker Plus**.
3. In Plus > Settings, import the old app's backup. Check the stock, revenue and History against the old app. Matching opening records are merged, not doubled.
4. Keep the old app and the backup until you have verified the transfer. Nothing in this installer clears or changes the old app's data.

Future Plus updates must keep the same signing certificate. CI now explicitly creates/restores a signing file at the configured location; cache eviction is still possible, so an owned, privately backed-up release keystore is required before treating this as a long-term production payment app. If Android reports a signing mismatch, stop; do not uninstall to bypass it.

## Receipt photos

Open History, select a transaction, then Receipt photos > Add receipt photo. Choose a receipt from your phone's photo/file picker. For a new photo, choose Take live receipt photo directly in this menu. Supplier purchase/expense forms also support live photos, originals and bundled offline OCR. The app stores its own compressed JPEG, so deleting the original phone photo does not remove the attached receipt. Photo orientation is preserved; the longest edge is resized to 1600 pixels.

Settings > Export full JSON backup now includes the actual receipt photos. Import merges transactions and photos without duplicating matching IDs. Existing version 1 backups are still accepted. Pairing credentials and unresolved payment sessions are intentionally not exported; resolve pending payments before changing phones. CSV does not contain images. Receipts remain visible after ledger corrections.

Limits: 1 MB per stored image, 100 photos, 24 MB of receipt images, 64 MB per JSON backup. Oversize imports fail without modifying the database. Backups contain private, unencrypted receipt images; keep a copy away from this phone.

## Set up your Stripe account

1. Open https://dashboard.stripe.com/register and create your own Australian Stripe account. Complete Stripe's business verification and bank/payout setup before real payments. Account approval is handled by Stripe.
2. Start in Stripe's test/sandbox environment. Create a Terminal location with your Australian business address and copy its `tml_...` location ID.
3. Deploy `backend/` on one Node 24 instance behind HTTPS, with persistent disk mounted at `/data`. The Dockerfile is included. Use a host that supports persistent disks; an ephemeral/serverless filesystem is insufficient. Costs depend on the host you choose.
4. Set these values privately in the host's environment settings, never in GitHub or this chat:
   - `STRIPE_SECRET_KEY`: the test secret key from that Stripe environment.
   - `STRIPE_LOCATION_ID`: the matching test Terminal location ID.
   - `MONSTER_APP_TOKEN`: a random token of at least 32 characters, generated locally with `node -e "process.stdout.write(require('crypto').randomBytes(32).toString('hex'))"`.
   - `MONSTER_DB_PATH`: `/data/payments.db`.
   - Leave `MONSTER_ALLOW_LIVE` unset during testing.
5. In Monster Tracker > Settings > Set up / connect Stripe, enter the backend HTTPS address and `MONSTER_APP_TOKEN`. Leave Enable real payments unchecked. The access token is encrypted using Android Keystore; your Stripe secret key never enters the app.
6. On a compatible physical phone, enter a sale amount and choose Try Stripe Tap to Pay (test mode). Stripe simulates payment; your real stock/revenue are unchanged. Emulators cannot exercise Tap to Pay device attestation.

## Your Galaxy A16 5G

Stripe lists the Samsung Galaxy A16 5G as supported. The device still needs Android 13+, working NFC, Google Play services/Play Store, a security patch from the past 12 months, a locked unmodified device, and stable internet. Location services and precise location permission must be available. Disable Developer options for live payments. Region-specific phone hardware can differ; runtime compatibility is checked by Stripe.

## Enable real payments only after testing

Create a live Terminal location. Configure the backend with your live secret key and matching live location, a **new persistent payment database path**, and `MONSTER_ALLOW_LIVE=true`. Preserve the test database. Enable real payments in the app only after resolving every pending test payment. The provided APK is non-debuggable, as required by Stripe for live Tap to Pay; the SDK is version 6.0.0. It is currently signed with a separate Android debug certificate for the Plus app, not a privately owned long-term production keystore. Keep this certificate stable for future updates; rotating it requires a planned migration and backups. Configure and back up your own release signing key before production deployment or wider distribution; migrate records through JSON when changing keys.

Cash/manual card ledger entries and receipt photos continue to work offline. Stripe Tap to Pay needs internet and sends payment data to Stripe through its SDK. Network and location permissions are now present; Camera permission is requested only for live receipt/barcode capture; no broad storage permission is requested.

## Payment recovery and refunds

The phone saves a checkout ID before networking. The backend stores that ID on durable disk and reuses a single Stripe PaymentIntent for retries, even after app/backend restart or a lost response. While a payment is unresolved, its cans are reserved; other available stock remains usable offline. Resume / check pending Stripe payment reuses it. Cancellation checks Stripe before discarding an unpaid checkout; processing or paid payments cannot be silently canceled. An uncertain creation older than 20 hours stops for manual Stripe reconciliation before Stripe's idempotency key retention could expire. Search Stripe using the `monster_sale_id` metadata; do not charge that sale again.

Live sales enter the ledger once Stripe confirms `succeeded` and provides the actual AUD settlement fee. If the fee is not available yet, the app says the payment was received and asks you to check status later; it does not charge again. A connected-network background job checks only the existing payment status and finalizes it exactly once after the actual fee is available. The PaymentIntent ID is retained in the transaction note. Test payments never enter the real ledger. Card numbers are handled by Stripe, not stored by this app.

Undo stays disabled for Stripe-paid or refund-linked source sales because a ledger correction alone cannot refund money. Use History > sale > Refunds & returned goods to request a full/partial Stripe refund through the authenticated original live backend, check/retry the same request, or reconcile Dashboard refunds. Failed/pending/canceled refunds remain traceable; a verified later failure appends a financial reversal. Original processing fees are retained, and actual additional refund fees are recorded when known. Received reusable cans require a separate confirmation. Disputes/chargebacks and webhook-driven automatic refund reconciliation are not included; check provider status explicitly. Stripe fees and settlement timing are not estimated or guaranteed by the app.

## Validation limits

CI builds the app and verifies its package, signature, non-debuggable manifest and lack of broad photo permissions. Host and emulator tests cover receipt backup/restore, migrations, local pending payment durability and existing accounting behavior. Backend tests use a fake Stripe adapter to check authentication, amount conflicts, concurrent retries and lost-response recovery. No Stripe account, deployed backend, physical Tap to Pay test or real charge was created during development.

Official references:
- https://docs.stripe.com/terminal/payments/setup-reader/tap-to-pay?platform=android
- https://docs.stripe.com/terminal/payments/setup-integration?terminal-sdk-platform=android
- https://docs.stripe.com/terminal/payments/collect-card-payment?terminal-sdk-platform=android

## Account and verification requirements (checked 2026-10-13)

Stripe's current official [Android Tap to Pay guide](https://docs.stripe.com/terminal/payments/setup-reader/tap-to-pay?platform=android) lists Australia and SDK 6.0.0. Review its full device conditions before live use; Android 13+ and NFC alone do not guarantee compatibility. This integration always requires connectivity for Stripe status/processing; offline card collection is not enabled.

Since you are under 18, follow Stripe's [account age requirements](https://support.stripe.com/questions/age-requirement-to-create-a-stripe-account): a legal guardian must be added as account owner before the account can accept payments/payouts. School permission does not configure or verify the Stripe account. Keep identity details and all credentials private in Stripe/your host; do not paste secret keys into the app, GitHub or chat.

After completing steps above, run one test payment on your physical phone and check the same PaymentIntent in Stripe's test Dashboard. Tap **Test refund / check same test refund** and check that refund in the same test Dashboard. Confirm your real inventory/revenue remain unchanged. The backend should retain one order/refund ID on retries. Test refunds exercise only test money. Live mode remains off until you explicitly supply live setup and a stable production signing key.

No real/test Stripe API write/readback, account verification, deployment, physical Tap to Pay collection or real refund was performed by this development environment. Nineteen backend tests use fake provider responses. Pending payment recovery is implemented; dispute/chargeback reconciliation is not automated. Provider refund status can change later, so use reconciliation to observe changes. Refund created timestamps come from Stripe, while report status-change dates are the known verification time, not an invented bank settlement date.

A pending payment reserves only its flavour/quantity. Available-stock displays and shopping alerts exclude that reservation; other cash/manual entries can continue offline. Resolve that flavour's payment before a physical count, and resolve all pending payments before phone transfer. Manual refund dates can explicitly stay unknown; incorrect manual refund records have append-only corrections. A physical return is independent of refund status and always needs your explicit confirmation.
