# Monster Business intelligence upgrade plan

## Inspection snapshot

The target application is the Flutter app in `universal/`, on
`feature/flutter-universal-tracker` at `d775056`. The branch is clean. The
root-level Java app is retained migration/accounting reference code; it is not
the active Flutter UI or the target for new business features. Android identity
is `au.monster.tracker.plus`, currently version 2.1.2+15.

The Flutter app stores a versioned, validated business-state document in local
SQLite (`business-tracker-v1.db`) using chunk rows and revision checks. Events
are append-only and replayed by `core/engine.dart`; money is integer AUD cents,
report dates use Australia/Perth, and inventory is valued FIFO by recorded
ledger order. Full portable backups validate/merge the same state. The shared
Flutter source targets Android and iOS.

| Domain | Existing implementation | Gap for this upgrade |
|---|---|---|
| Products / flavours | Products with category, variant, barcode, sell price, deal price, cost hint, minimum stock, archive state | No dedicated Monster flavour identity/volume fields beyond variant text |
| Inventory / costs | Append-only restock, sale, damage, missing, transfer and return events; FIFO lot replay | New purchase UI is one product at a time; no purchase-level/multi-line ledger view |
| Sales / refunds | Actual sale totals, cash/card, fees, manual refunds, explicit goods returns, undo/corrections | No customer link; returns do not record condition |
| Profit | FIFO COGS, refunds, sales-only product profit, current stock estimates, operating expenses and preserved net result | Sales/profit figures exist; need expanded flavour analytics and validation surface |
| Stocktaking | Product-level counts can be recorded as adjustments | No snapshot session, movement reconciliation or stocktake history screen |
| Retailer prices | None in the Flutter domain | No observations, retailer source adapters, alerts, comparison or scheduler |
| Purchasing | Existing product restock event records actual quantity and cost; imported legacy supplier docs remain in backup/history | No current multi-product purchase capture, pack metadata, purchase ledger or correction flow |
| Customers | None | Optional privacy-conscious customer identity and linked sales |
| Forecast/restock | Minimum-stock alerts and basic quantity/pack shopping estimates | No velocity, demand confidence, cost-aware planner or backtest |
| Persistence / integration | SQLite atomic save/revision protection; backup merge; one-way Sheets mirror; OS-managed backup/upload retries | No server-side retailer scheduler or backend in active Flutter stack |
| Auth / access | Local device ownership; no multi-user authentication/roles | Responsible user attribution needs an identity system if multi-user is required |

### Dependency map

```text
Shared event/lot ledger + integer-cent and Perth-time rules
  ├─ Purchases → FIFO stock and cost → margins, flavour profit, restock costs
  ├─ Sales/refunds/returns → realised revenue and profit → customer history
  ├─ Stocktake snapshots + intervening movements → audited adjustments
  ├─ Price observations → verified offers → drop alerts + deal calculator
  └─ Sales + sellable stock + costs + lead times → planner + forecasts/backtests
```

Retail observations are reference data only and never create purchase events.
Purchase receipts create stock only when actual goods are recorded as received.
Sales, refunds, stock movements and observations must retain their own immutable
identifiers and backup/import idempotency.

## Phased implementation

1. **Foundation, purchase history, sales/profit reconciliation.** Keep restock
   events as the costed stock source of truth. Add purchase grouping/line facts
   to those events, multi-product purchase entry and a purchase history view;
   enforce idempotent purchase IDs and preserve legacy backups. Verify FIFO,
   existing sales totals, refunds, write-offs, reports and restore compatibility.
2. **Stocktake mode.** Add snapshot sessions and counts, show discrepancy
   preview, then calculate/apply append-only adjustment events against the
   current replayed stock so movements posted during counting are reconciled.
   Confirmation must be idempotent and auditable.
3. **Price observation foundation and tracker.** Add retailer/offer identity,
   provenance, verification and observation timestamps. Provide manual capture
   and comparison first. Then assess permitted public retailer APIs/pages and
   deploy a locked, persistent Wednesday 09:00 Australia/Perth scheduler only
   for integrations actually verified. This app currently has no server host.
4. **Price alerts and deal calculator.** Reuse only verified observations,
   deduplicate alerts by offer/change identity, and optimize exact-compatible
   pack combinations under user constraints. No purchase action is automated.
5. **Sales intelligence.** Add flavour sorting/performance, margin thresholds
   and optional customer linkage on the existing sales events. Keep anonymous
   sales and existing transaction/refund history valid.
6. **Restock and forecasting.** Combine ledger sellable units, sales velocity,
   actual lots, manual thresholds and verified offers. Start with explainable
   averages and rolling backtests; withhold precise numbers when history or
   availability evidence is inadequate.
7. **Integration and release.** Complete backup/restore, Sheets preview/mirror,
   accessibility/regression tests, in-place Android upgrade and unsigned iOS
   compilation. Build through the existing PR workflow; do not publish stores.

## Migration, backup and test strategy

The state format is currently version 1 and SQLite schema version 4. Prefer
optional, validated fields on existing immutable event records where that keeps
one source of truth; if new normalized collections are necessary, add a state
format migration that accepts old backups and preserves unknown legacy data.
Never rewrite existing events or reconstruct their prices/costs from current
product settings. A release change must increase Android `versionCode` and keep
the existing package/signing identity. Before any migration release, run the
existing populated 2.1.0-to-2.1.2 in-place-upgrade path and extend it with the
new release candidate. Save a full backup first and retain rollback evidence.

Validation layers: pure Dart FIFO/revenue/date/calculator tests; backup roundtrip
and legacy-version fixtures; SQLite idempotency and stale-writer tests; widget
tests for confirm/preview states; Flutter analyze/test; existing Java parity and
host scripts; signed Android upgrade emulator; iOS no-code-sign compile. A
retailer adapter cannot pass collection acceptance using fixtures alone: each
retailer needs source, location, flavour/volume matching and repeat-run evidence.

## Assumptions and external blockers

- “Product” maps to the existing product + variant identity; can volume and
  exact multipack composition need explicit fields before retailer matching.
- Current costs are FIFO ledger costs; zero-cost lots may mean either truly free
  stock or missing data, so calculations must retain an incomplete state.
- Current Flutter return events have no sellable/damaged condition. A new
  condition field needs a backwards-compatible default and must not silently
  label old returns damaged or sellable without showing the assumption.
- The live app has no authenticated multi-user identities, backend host or
  retailer credentials. User attribution, persistent server jobs and some
  retailer collection depend on owner-selected hosting/access and permitted
  retailer data sources. Manual price observation is the safe fallback.
- Customer notes/contact fields should be optional and local-only unless the
  existing one-way Sheets preview explicitly opts them in; backups remain under
  the user's existing full-backup controls.
- A live Wednesday job, retailer coverage, push/email alerts, and production
  data migration cannot be claimed from a local Flutter test build.
