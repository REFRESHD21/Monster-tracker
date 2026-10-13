# Upgrade progress

## Phase 1 — built and verified

- Database version 1/2 → 3 adds tables and triggers; it does not rebuild, reset, rename or alter the existing ledger, settings, pending commands, opening IDs or dates.
- Existing ledger rows are backfilled into an append-only audit. New ledger rows are audited by a SQL trigger in the same transaction, including the original undo behavior.
- Offline supplier purchases have reviewed supplier/reference/date, multiple lines, multipacks, gross line costs, actual GST shown, notes and original JPG/PNG/PDF attachments. The date can explicitly remain unknown.
- Receipts can be imported or photographed. Original bytes are retained in private SQLite, immutable, and SHA-256 fingerprinted. A receipt already linked to a saved document or a repeated supplier/reference is rejected instead of creating another purchase.
- Document confirmation does **not** add stock. A separate goods-received confirmation supports partial deliveries. Quantity and cumulative cost allocation are checked inside the same transaction as the restock and delivery/audit rows; repeated delivery IDs are idempotent.
- Operating expenses and mixed purchase expense lines are recorded without changing stock. Expense undo/cancellation appends a correction; no saved row is edited/deleted. Cancelling a purchase stops additional delivery confirmations, while existing deliveries remain explicit ledger records and can be undone through History.
- Dashboard retains the existing cash result after stock and adds expenses/result after stock and expenses. Purchase invoice totals are retained separately; this phase is not a profit/COGS or BAS report. Received stock carries allocated gross cost; unreceived costs are not yet part of the legacy inventory cash-result calculation.
- Version-3 full JSON backup includes documents, receipts (original bytes), deliveries, corrections and audit history. Version-1 and version-2 backups remain readable and merge without clearing the newer domain. Files and receipts have size limits (64 MB full JSON, 16 MB each receipt); oversized exports fail visibly instead of writing a truncated file.
- Privacy: receipts stay app-private; selected originals may be opened in an installed offline viewer via a narrow read-only URI grant. No database URI or additional network permission was added; Phase 2 requests camera access only for capture/scanning. Existing Stripe/network setup from main is preserved.

## Validation

64 host checks passed: 29 original Java checks, ten purchase/receipt/backup checks, 24 SQLite checks (including v1/v2 migrations), and original-ledger parity across 100 scenarios. Six Android instrumentation checks were added for genuine v1 migration, partial deliveries/idempotency, duplicate attachments, expense undo, and full backup/restore, making 21 in total. The Phase 1 workflow checked all 21 before APK publication; later phases increase this count. Phase 1 CI run 38388080119 passed Android unit tests, all 21 airplane-mode emulator checks, and APK package/signature validation. Camera/document-picker behavior requires phone testing.

## Remaining phases

2. Implemented in the current Phase 2 changes; built and verified (details below).
3. Consistent historical costing, profit and GST registration/tax treatment settings, period/flavour reports and CSV/PDF exports.
4. Scheduled/encrypted backups, restore/recovery improvements and optional cloud destination.
5. Stripe Terminal test integration, secure server authentication/connection tokens, verified payments/refunds and reconciliation. No payment processing or offline-card capability is claimed in Phase 1. Current Australian/device/account requirements will be checked before implementation; secrets will never be bundled into the APK.

Phase 1 integration preserves the current Plus application ID/signing path, original photo receipts, encrypted payment settings and Stripe checkout/backend. A genuine v2 upgrade test additionally verifies photo bytes and pending payment persistence. Partial delivery cost allocation was hardened for undo/re-receive rounding: it allocates the remaining actual invoice cost, so all received costs still sum exactly to the invoice line.

## Phase 2 — built and verified

- Database version 4 adds per-flavour products, stock thresholds, supplier/pack estimates, saved barcodes, immutable transaction flavour allocations and explicit stock transfers. Existing inventory/history remains in “Monster — unassigned flavour”; assign current cans with an audited transfer without rewriting historical rows or adding stock.
- Native live camera captures full-resolution receipt JPGs entirely offline. Import JPG/PNG/PDF remains available. Camera permission is requested only when scanning/capturing; declining it leaves manual/import entry available. No broad storage permission.
- Bundled ML Kit Latin OCR scans images and up to 20 PDF pages (the entire original is retained). It suggests supplier/reference/date, products, pack quantities, unit/line prices, total and GST. Review is mandatory; suggested dates remain unknown if not detected. Suggestions never confirm delivery or add inventory. All inferred values can be edited before saving; an attached photo can be previewed directly in the app.
- Bundled ML Kit retail-barcode scanning supports sales, purchase lines and product/count lookup. Manual assignments/search work offline. Barcode reassignment requires confirmation and is audited. No external barcode database is used.
- Sales and card checkout retain a durable flavour allocation, validate available stock for that flavour, and preserve their mapping through restart/retry/undo. Legacy events without a mapping remain unassigned. Existing Stripe integration is preserved; test/live rules and online requirements are unchanged.
- Shopping lists show on-hand, outstanding confirmed purchase orders, required quantities, pack rounding and estimated supplier cost. New purchases only increase inventory after explicit received-goods confirmation. Physical counts create visible missing/restock adjustments; stock transfers are append-only.
- Full version-4 JSON backups include products, barcodes, settings, stock mappings/transfers and the existing documents/receipts/audit. Restore rejects invalid links, barcode/identity conflicts and negative combined inventory without deleting existing history; price/stock-setting restoration requires the existing restore confirmation and settings changes are audited. Legacy backups still work.
- Host suite includes ten catalogue/OCR checks and three version-4 SQL migration checks. Android suite adds per-flavour sale/undo/deduplication, oversale rejection, catalogue restore/restart, bundled barcode and OCR first-use in airplane mode, and camera-screen fallback (27 checks total). Physical camera capture quality and retail barcode recognition still need phone testing.

Phase 2 run [38392426997](https://github.com/REFRESHD21/Monster-tracker/actions/runs/38392426997) passed host checks, Android unit tests, all 27 airplane-mode emulator checks and APK package/signature validation. Its artifact is `monster-tracker-apk` / `Monster-Tracker-1.3.apk`.

## Phase 3 — implemented, Android verification pending

- Version 5 adds immutable historical GST snapshots and future-only audited tax settings. No event, receipt, purchase or stock table is rebuilt. Existing history defaults to unregistered/no inferred credits; GST registration defaults OFF.
- FIFO inventory valuation uses immutable ledger insertion order (not backdated sale dates), cents-exact remaining lot costs and flavour transfers. Transfers now retain their ledger anchor so same-millisecond activity and restored opening ingestion times do not change cost ordering. Existing version-4 transfers remain readable.
- Later stock purchases and settings changes do not reprice earlier sales. Undo returns the original consumed costs; undo of a consumed restock withdraws available stock and shows any valuation difference as an explicit correction loss/gain. Existing undo remains supported.
- Reports show gross revenue, cash/card, actual recorded fees, COGS, gross profit, operating expenses, missing/damaged/lost stock valuation, estimated net profit, GST estimates and current inventory value. Flavour gross profit excludes shared fees/expenses. Daily, weekly, monthly, quarterly, calendar-year, Australian financial-year and all-history filters use Perth time. Unknown historical dates only appear in All history and are explicitly counted.
- Taxable/GST-free/input-taxed flavour settings apply to future entries. Inclusive taxable sale GST and actual supplier/expense GST credits are stored with each event/document. Partial delivery GST is allocated exactly once; no credit is inferred from a receipt that is absent. Manual stock entry supports actual receipt GST. Settings/restore do not rewrite tax history. Input-taxed inventory does not receive a credit.
- CSV exports contain detailed signed financial rows/corrections. Native PDF exports contain period totals, flavour profit and calculation notes. Both use the Android file picker and work offline.
- These are bookkeeping estimates, not a BAS. Unreceived invoice costs, income tax and unrecorded expenses are excluded. Existing corrections are not payment refunds; Stripe refunds/reconciliation still require Phase 5.
- Version-5 JSON backups include historical tax snapshots and GST settings, with cross-reference/conflict validation and audited settings restore. Legacy versions 1–4 remain readable.
- Host checks include 11 FIFO/GST/report calculations and two version-5 migration/immutability checks. Five additional Android checks cover future-only GST across restart, partial receipt credits, financial backup/restore, v4 migration and native PDF/offline report startup (32 checks total).
