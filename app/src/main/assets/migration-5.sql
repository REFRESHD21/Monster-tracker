CREATE TABLE finance_settings (key TEXT PRIMARY KEY, body TEXT NOT NULL);
INSERT INTO finance_settings VALUES('gst','{"registered":false,"expenseCredits":true}');
CREATE TABLE finance_tax (source_id TEXT PRIMARY KEY, kind TEXT NOT NULL CHECK(kind IN ('ledger','document')), body TEXT NOT NULL);
CREATE TABLE finance_tax_plans (source_id TEXT PRIMARY KEY, body TEXT NOT NULL);
CREATE TRIGGER finance_tax_no_update BEFORE UPDATE ON finance_tax BEGIN SELECT RAISE(ABORT,'Historical tax snapshots are immutable'); END;
CREATE TRIGGER finance_tax_no_delete BEFORE DELETE ON finance_tax BEGIN SELECT RAISE(ABORT,'Historical tax snapshots are immutable'); END;
