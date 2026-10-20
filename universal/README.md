# Business Tracker 2.3.3 (20)

This release adds a persisted **Business Funds** ledger to the Flutter app. Cash
and card sale proceeds increase funds by the recorded revenue less recorded
payment fees. IOU sales do not increase available funds until money is actually
received. Sale IDs are deduplicated so retries/reopening do not count proceeds
twice; undoing a paid sale reverses its funds entry. Manual Add money, Take out
and Recount actions remain available, and stock purchases reduce funds only
when the purchase form's funds checkbox is enabled.

The sale cart supports an opt-in **mix-and-match pair deal** for individual
products, including different drink flavours. The default pair total is AUD
$6.00 and can be edited in the sale sheet. Every two individual cans receive
the configured pair price; an odd leftover can keeps its normal unit price.
Bundles are excluded from pair pricing. The saved sale total is the amount
entered/confirmed at sale time; historical sale totals are not repriced.

Android package remains `au.monster.tracker.plus`; this update uses
versionCode **20** and versionName **2.3.3**. Export a full backup before
installing an update, and install over the existing app rather than uninstalling
it so local records are retained. GitHub Actions verifies the release artifact's
package, version, signing certificate and non-debuggable status before upload.

---

# Business Tracker 2.2.0 (16)

Current Flutter improvements preserve sale totals and existing records, add quick
sales, product-specific deals and safe archive/restore. Native Google account
connection, new/existing spreadsheet selection, report preview and retry-safe
one-way uploads are implemented. The owner-supplied public Web OAuth client ID is included in the Android build.
Google Cloud Android-client/consent configuration and live account verification
remain owner setup; see
[Google Sheets setup and testing](GOOGLE_SHEETS_SETUP.md). Without configured IDs,
the build explicitly reports setup is required. Apps Script is an advanced option.

## Faster sales and safe product removal (included in 2.1.0)

Record sale is available above the bottom navigation on every screen. Tap a
product in the active Products list (or choose one from Record sale), select
1 item, an explicitly configured 2-item deal, or a custom quantity, check the
total and visible Cash/Card choice, and confirm once. Fees, GST, receipts/OCR,
date and notes remain under More details. The last successful sale's payment
method is saved atomically with that sale and is always visible next time.
One draft ID plus a disabled confirmation while saving prevents duplicate taps.

Configure each product's optional **2-item deal TOTAL** in Product options →
Edit product / prices. A blank value disables it. Existing products start with
no deal; no global or another product's deal is inherited. Custom quantities
use the normal unit price until the total is manually changed. Existing sale
amounts are never recalculated. New sales also retain a product-name snapshot.

Use Product options → Remove / archive product. Permanent deletion is allowed
only with zero stock, no history and no other references. Products with history
or references may be archived once stock and pending items are resolved. The
removal dialog explains blockers. Archived products are excluded from active
lists, low-stock alerts, barcode sales and sale/transfer pickers. Products →
Archived products offers Restore and displays any stock received later through
a historical return. History, names, reports, receipts and FIFO costs remain.
Archive/deal settings and the last payment method are included in full backups.
Older 2.0.0 backups remain readable; their missing settings mean active/no deal.

## Sales & product profit

The Home overview separates actual sales-based product results from estimates
for current stock. Reports support Today, week, month, quarter, year, financial
year, all history and a custom Perth date range. Product rows can be sorted by
revenue, product profit, units sold or estimated future revenue. Sales profit
uses actual recorded transaction revenue after refunds and the existing FIFO
COGS rows; it does not subtract fees, expenses or damaged/missing stock losses.
Future inventory estimates use each product's current selling price and the
remaining FIFO lots. Unknown dates stay out of bounded date ranges.

The ledger stores costs as integer cents and treats zero-cost stock as incomplete
when the current product cost setting is positive. This can flag genuinely free
stock too because the ledger cannot distinguish a free purchase from an
unrecorded cost. This check applies to both current inventory and sold units;
zero-cost rows remain usable when the product is explicitly configured with a
zero purchase cost. A product with no configured positive selling
price is likewise shown as incomplete while stock remains. Physical returns
follow the existing behavior and re-enter FIFO sellable stock; the current data
model does not label returned goods as damaged, so mark damaged returns with the
existing damaged-stock adjustment immediately after receiving them. The app
does not infer an inventory return from a money refund. Record the refund and
physical return separately as the existing history requires.

The Android version is **2.2.0 (16)** with the same package and existing signing
certificate. CI opens the actual shipped 2.1.0 release on populated records,
then installs 2.2.0 over it without uninstalling. Physical-device checks and
live Sheets setup remain as described below. No payment-provider integration
or store publication is part of this update.

# Business Tracker 2.0

Shared Flutter application for Android and iPhone, developed from Monster Tracker
1.6.3 (`feature/sheets-compatible-update`, e0d3dea). The Java app at the repository
root remains the accounting oracle and legacy database exporter; `universal/` is
the new application. There is no payment processing in the Flutter application.

## Build and test

Use Flutter **3.35.7**, JDK 17 and Android SDK. Run from the repository root:

```sh
bash scripts/test-core.sh
java -m jdk.compiler/com.sun.tools.javac.Main -cp .build/core -d .build/core scripts/flutter/ParityFixtures.java scripts/flutter/DomainFixtures.java
java -cp .build/core au.monster.tracker.ParityFixtures
java -cp .build/core au.monster.tracker.DomainFixtures
python3 scripts/flutter/bootstrap.py
cd universal
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

`bootstrap.py` generates native scaffolds using the pinned Flutter SDK, preserves
reviewed platform overlays, and copies a fixed allowlist of original Java backup
classes. It excludes the original activities, Stripe SDK and payment backend.
Do not run it twice on the same generated scaffold; regenerate Android/iOS from a
clean checkout when changing toolchains. The Android build requires the **existing**
compatible keystore via `MONSTER_DEBUG_KEYSTORE`; it must not silently generate a
replacement. The CI certificate gate runs before building an Android update.
The cache is compatibility infrastructure, not an owned production release key.

## Migration and records

- The Android package remains **au.monster.tracker.plus**; versionCode is **15**.
- On first launch, an existing `monster-offline.db` is exported through the original
  Java validators. A pending payment checkout blocks migration rather than losing
  a reserved or potentially paid sale. Resolve such checkouts in 1.6.3 before updating.
- The original database is retained. A private `pre-flutter-migration.json` safety
  copy and an immutable SQLite safety row are created. New records live in
  `business-tracker-v1.db`. Never uninstall or clear data to fix an upgrade error.
- A new installation does not open the legacy database and starts with no products
  or transactions. There are no fabricated 24-can/four-missing opening records.
- Original events, unknown dates, product IDs, allocations, transfers, tax snapshots,
  refund observations, supplier documents, audit records and original receipt bytes
  are preserved in the legacy source embedded in every full universal backup.
- The normalized historical ledger and remaining FIFO lots are replayed in Dart.
  It is checked against Java oracle fixtures, including multi-domain schema-6 data.
- Historical stock with no original product identity remains explicitly unassigned.
  It is not guessed to be a particular drink or skincare item.
- Universal exports use a separately versioned format. Original Monster-compatible
  export remains available, but contains only the original migration history.
  Older Monster versions cannot read new universal transactions.
- Restore is validated before an atomic SQLite save. Duplicate imports are harmless;
  conflicting or independent business histories are rejected. A newer backup for
  the same business can extend a matching prefix; an older backup cannot roll back
  existing events. Restore previews the imported settings before confirmation.
- Cash/card labels are bookkeeping only. A refund never adds stock; physically
  returned goods restore the original FIFO cost only after explicit receipt.

Each installation has a generated business ID, its own database and its own
Sheets credentials. Deliberately restoring another business's full backup into an
empty installation transfers that business; it does not create automatic sharing.

## Workflow

Home shows inventory value, estimated net profit and in-app low-stock alerts.
Products have a name, category, variant, photo, barcode, minimum stock, purchase
cost and selling price. Each variant is an independent stock item. Sale/restock
forms suggest a quantity × unit-price total until you edit the **total** amount
yourself. Custom totals support bundles and negotiated prices. Missing/damaged stock, manual refunds, explicit physical
returns and append-only corrections are supported. Prices never reprice history.

Receipts accept original JPG/PNG/PDF attachments, camera images and offline text
recognition suggestions. OCR does not save transactions automatically. Original
supplier documents and their receipt/audit associations are readable/exportable.
New stock is received directly on a product; the old multi-line supplier invoice
and partial-delivery editor is not reimplemented in this version. Its historical
records remain intact. Multiple original barcodes are retained in source and Sheets;
the product editor currently manages one primary barcode per variant.

Themes: light, dark, green, ocean, purple and warm neutral.
Reporting uses AUD integer cents, FIFO and Perth dates, including the Australian
financial year. Financial CSV amounts are **integer cents** and headers identify the
export's units in its filename. Inventory value is current, not a period-end snapshot.
GST snapshots are entered explicitly; eligibility is not inferred from a receipt.
Settings also exports sales/stock history with quantities and correction references.
Portable limits are 64 MB, 100,000 normalized events and 10,000 products; oversize
writes fail visibly before changing records.

After the initial Java-to-Flutter framework update, reconfigure Google Sheets and automatic backup
scheduling/folder delivery in Settings. Existing portable backups, original Android
recovery copies and their passwords remain usable.

## Backups and automatic work

JSON exports include receipt/photo bytes but are unencrypted. Portable encrypted
backups use AES-256-GCM with PBKDF2-HMAC-SHA256 (310,000 iterations), random salt and
nonce, and authenticated metadata. Java `MONSTERBK1` encrypted backups remain
readable; new backups use `BUSINESSBK1`. Passwords cannot be recovered. Scheduled
passwords and Sheets tokens are stored using platform secure storage and excluded
from portable exports. Schedules must be configured again after transferring phones.

Recovery copies are written to a temporary file, authenticated and atomically
renamed before they become selectable. Scheduled recovery keeps seven verified
encrypted app-private copies and can
copy them to a user-selected document-provider folder, with byte-for-byte readback
verification. Provider access, including iCloud/Drive behaviour, requires device
verification. Original Android recovery copies remain exportable. These are
not protection against uninstalling, clearing data, loss or device reset: export
copies outside the app as well. Manual export uses the system document picker.
Foreground/resume retries and OS-managed background jobs handle optional uploads
and backups. Android/iOS may delay or skip execution; no exact timing is promised.
Low-stock alerts are shown inside the app, not background push notifications.

## Sheets

Deploy `sheets/Universal.gs` in a separate Apps Script project (or replace the old
receiver intentionally). Set `SPREADSHEET_ID` and a random `SYNC_TOKEN` of at least
32 characters in Script Properties. Deploy as a web app executing as its owner,
with access Anyone, and enter its HTTPS `/exec` URL and token in Settings.
Use a separate spreadsheet/token for each independent business.

The `UniversalRecords` tab receives normalized events, versioned product metadata,
refunds, supplier documents, original audit/delivery records and receipt metadata.
Photos/PDF bytes, backup passwords and pairing tokens are not uploaded. Automatic jobs send only records not acknowledged locally; manual Upload now
resends the complete mirror. Retries
are idempotent by business ID + record ID; conflicts are rejected. Do not edit
receiver-managed rows. Notes remain inside JSON text cells to avoid formula
execution. This is an audit mirror, not a ready-made financial dashboard or backup.
Script limits: 50 records per batch, 45,000 characters per record, 50,000 rows.
No live connection is configured by installation alone.

## iPhone preparation

The shared source, Swift AppDelegate, privacy purpose strings, background task
identifiers and iOS 15.5 deployment target are prepared. Build on macOS with Xcode:

```sh
python3 scripts/flutter/bootstrap.py
cd universal
flutter build ios --release --no-codesign
```

An unsigned successful build is compilation evidence, not an installable iPhone
release. Owner-controlled Apple Developer enrollment, bundle-ID registration,
certificates/profiles, App Store Connect configuration and a signed archive are
needed for TestFlight. External testers require beta review; TestFlight builds
expire after 90 days. Confirm the actual iPhone supports iOS 15.5 or later and test
camera, barcode, document export, secure storage and background timing on it.
An APK cannot be installed on iPhone. No upload or store publication is automatic.

## Production release preparation

Before Google Play, replace the cached test-signing arrangement with an owned,
securely backed-up release-key plan and a verified compatible signing transition.
Do not simply use a new certificate under the same package and ask users to
uninstall. Configure Play App Signing and separate upload-key secrets deliberately;
keep production keys out of PR jobs. Before either store, complete privacy/data
safety disclosures, dependency/permission review, developer-account requirements,
icons/screenshots, support/privacy URLs and applicable testing/review requirements.
`PRIVACY_DRAFT.md` is a factual starting point, not a published policy.
