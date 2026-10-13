CREATE TABLE events (
 seq INTEGER PRIMARY KEY AUTOINCREMENT,
 id TEXT NOT NULL UNIQUE,
 timestamp INTEGER,
 recorded_at INTEGER NOT NULL,
 type TEXT NOT NULL CHECK(type IN ('single','deal','restock','missing','damaged','lost','undo')),
 quantity INTEGER NOT NULL CHECK(quantity >= 0 AND quantity <= 10000),
 payment TEXT NOT NULL CHECK(payment IN ('cash','card','none')),
 revenue INTEGER NOT NULL CHECK(revenue >= 0 AND revenue <= 10000000),
 fee INTEGER NOT NULL CHECK(fee >= 0 AND fee <= revenue),
 cost INTEGER NOT NULL CHECK(cost >= 0 AND cost <= 10000000),
 note TEXT NOT NULL CHECK(length(note) <= 500),
 target TEXT REFERENCES events(id),
 CHECK((type='undo' AND target IS NOT NULL AND quantity=0 AND payment='none' AND revenue=0 AND fee=0 AND cost=0) OR (type!='undo' AND target IS NULL AND quantity>=1)),
 CHECK((type IN ('single','deal') AND payment IN ('cash','card') AND cost=0 AND ((type='single' AND quantity=1) OR (type='deal' AND quantity=2))) OR (type NOT IN ('single','deal') AND payment='none' AND revenue=0 AND fee=0)),
 CHECK(payment!='cash' OR fee=0),
 CHECK(type='restock' OR cost=0)
);
CREATE UNIQUE INDEX one_undo_per_event ON events(target) WHERE type='undo';
CREATE TABLE settings (key TEXT PRIMARY KEY, value INTEGER NOT NULL CHECK(value >= 0 AND value <= 10000000));
CREATE TABLE pending (id INTEGER PRIMARY KEY CHECK(id=1), json TEXT NOT NULL);
CREATE TRIGGER no_event_update BEFORE UPDATE ON events BEGIN SELECT RAISE(ABORT,'Transaction history is append-only'); END;
CREATE TRIGGER no_event_delete BEFORE DELETE ON events BEGIN SELECT RAISE(ABORT,'Transaction history is append-only'); END;
