# Upgrade progress

## Phase 1 — implemented, awaiting this commit's Android build

- Database version 1/2 → 3 adds tables and triggers; it does not rebuild, reset, rename or alter the existing ledger, settings, pending commands, opening IDs or dates.
- Existing ledger rows are backfilled into an append-only audit. New ledger rows are audited by a SQL trigger in the same transaction, including the original undo behavior.
- Offline supplier purchases have reviewed supplier/reference/date, multiple lines, multipacks, gross line costs, actual GST shown, notes and original JPG/PNG/PDF attachments. The date can explicitly remain unknown.
- Receipts can be imported or photographed through the installed camera app. Original bytes are retained in private SQLite, immutable, and SHA-256 fingerprinted. A receipt already linked to a saved document or a repeated supplier/reference is rejected instead of creating another purchase.
- Document confirmation does **not** add stock. A separate goods-received confirmation supports partial deliveries. Quantity and cumulative cost allocation are checked inside the same transaction as the restock and delivery/audit rows; repeated delivery IDs are idempotent.
- Operating expenses and mixed purchase expense lines are recorded without changing stock. Expense undo/cancellation appends a correction; no saved row is edited/deleted. Cancelling a purchase stops additional delivery confirmations, while existing deliveries remain explicit ledger records and can be undone through History.
- Dashboard retains the existing cash result after stock and adds expenses/result after stock and expenses. Purchase invoice totals are retained separately; this phase is not a profit/COGS or BAS report. Received stock carries allocated gross cost; unreceived costs are not yet part of the legacy inventory cash-result calculation.
- Version-3 full JSON backup includes documents, receipts (original bytes), deliveries, corrections and audit history. Version-1 and version-2 backups remain readable and merge without clearing the newer domain. Files and receipts have size limits (64 MB full JSON, 16 MB each receipt); oversized exports fail visibly instead of writing a truncated file.
- Privacy: receipts stay app-private; selected originals may be opened in an installed offline viewer via a narrow read-only URI grant. No database URI or additional runtime/network permission was added. Existing Stripe/network setup from main is preserved.

## Validation

64 host checks passed: 29 original Java checks, ten purchase/receipt/backup checks, 24 SQLite checks (including v1/v2 migrations), and original-ledger parity across 100 scenarios. Six Android instrumentation checks were added for genuine v1 migration, partial deliveries/idempotency, duplicate attachments, expense undo, and full backup/restore, making 21 in total. The workflow checks all 21 before APK publication. Camera/document-picker behavior requires phone testing.

## Remaining phases

2. On-device OCR, barcode camera scanning, per-flavour catalog/low-stock/shopping lists.
3. Consistent historical costing, profit and GST registration/tax treatment settings, period/flavour reports and CSV/PDF exports.
4. Scheduled/encrypted backups, restore/recovery improvements and optional cloud destination.
5. Stripe Terminal test integration, secure server authentication/connection tokens, verified payments/refunds and reconciliation. No payment processing or offline-card capability is claimed in Phase 1. Current Australian/device/account requirements will be checked before implementation; secrets will never be bundled into the APK.

Phase 1 integration preserves the current Plus application ID/signing path, original photo receipts, encrypted payment settings and Stripe checkout/backend. A genuine v2 upgrade test additionally verifies photo bytes and pending payment persistence. Partial delivery cost allocation was hardened for undo/re-receive rounding: it allocates the remaining actual invoice cost, so all received costs still sum exactly to the invoice line.
