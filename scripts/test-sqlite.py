#!/usr/bin/env python3
"""Host SQLite tests execute the exact Android schema. These are not device tests."""
import json,sqlite3,tempfile,unittest,pathlib,xml.etree.ElementTree as ET
ROOT=pathlib.Path(__file__).resolve().parent.parent
SCHEMA=(ROOT/'app/src/main/assets/schema.sql').read_text()
BACKUP=json.loads((ROOT/'.build/host-backup.json').read_text())
COLS=('id','timestamp','recorded_at','type','quantity','payment','revenue','fee','cost','note','target')
def millis(s):
 if s is None:return None
 import datetime
 return int(datetime.datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()*1000)
def values(e):
 e=dict(e);e['timestamp']=millis(e['timestamp']);e['recorded_at']=millis(e['recordedAt']);return tuple(e[k] for k in COLS)
def insert(db,e):db.execute('INSERT INTO events('+','.join(COLS)+') VALUES('+','.join('?' for _ in COLS)+')',values(e))
class LocalDatabaseTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.path=pathlib.Path(self.tmp.name)/'tracker.db';self.db=sqlite3.connect(self.path)
  self.db.execute('PRAGMA foreign_keys=ON');self.db.execute('PRAGMA journal_mode=WAL');self.db.executescript(SCHEMA)
  with self.db:
   for e in BACKUP['events'][:2]:insert(self.db,e)
   self.db.executemany('INSERT INTO settings VALUES(?,?)',[('single',350),('deal',600)])
   self.db.execute('PRAGMA user_version=1')
 def tearDown(self):self.db.close();self.tmp.cleanup()
 def test_opening_seed_and_unknown_dates(self):
  self.assertEqual(self.db.execute('SELECT count(*) FROM events').fetchone()[0],2)
  self.assertEqual(self.db.execute('SELECT sum(quantity) FROM events WHERE type="restock"').fetchone()[0],24)
  self.assertEqual(self.db.execute('SELECT sum(quantity) FROM events WHERE type="missing"').fetchone()[0],4)
  self.assertEqual(self.db.execute('SELECT count(*) FROM events WHERE timestamp IS NULL').fetchone()[0],2)
 def test_persistence_and_restart_no_network(self):
  with self.db:insert(self.db,BACKUP['events'][2])
  self.db.close();self.db=sqlite3.connect(self.path)
  self.assertEqual(self.db.execute('SELECT count(*) FROM events').fetchone()[0],3)
  self.assertEqual(self.db.execute('SELECT revenue,fee FROM events WHERE type="deal"').fetchone(),(600,25))
  self.assertIn(self.db.execute('PRAGMA user_version').fetchone()[0],(1,2,3))
 def test_unique_id_enforced_and_duplicate_rollback(self):
  e=BACKUP['events'][2]
  with self.db:insert(self.db,e)
  with self.assertRaises(sqlite3.IntegrityError):
   with self.db:insert(self.db,e)
  self.assertEqual(self.db.execute('SELECT count(*) FROM events').fetchone()[0],3)
 def test_transaction_failure_is_atomic(self):
  with self.assertRaises(sqlite3.IntegrityError):
   with self.db:
    insert(self.db,BACKUP['events'][2]);insert(self.db,BACKUP['events'][0])
  self.assertEqual(self.db.execute('SELECT count(*) FROM events').fetchone()[0],2)
 def test_history_cannot_be_deleted_or_rewritten(self):
  with self.assertRaises(sqlite3.IntegrityError):self.db.execute('DELETE FROM events')
  with self.assertRaises(sqlite3.IntegrityError):self.db.execute('UPDATE events SET quantity=25')
  self.assertEqual(self.db.execute('SELECT count(*) FROM events').fetchone()[0],2)
 def test_duplicate_correction_and_unknown_reference_rejected(self):
  u={'id':'undo-sql-test1','timestamp':'2026-10-12T00:00:00Z','recordedAt':'2026-10-12T00:00:00Z','type':'undo','quantity':0,'payment':'none','revenue':0,'fee':0,'cost':0,'note':'Correction','target':'opening-missing-v1'}
  with self.db:insert(self.db,u)
  u['id']='undo-sql-test2'
  with self.assertRaises(sqlite3.IntegrityError):
   with self.db:insert(self.db,u)
  u['target']='unknown-target'
  with self.assertRaises(sqlite3.IntegrityError):
   with self.db:insert(self.db,u)
 def test_json_restore_records_match(self):
  with self.db:
   for e in BACKUP['events']:
    if not self.db.execute('SELECT 1 FROM events WHERE id=?',(e['id'],)).fetchone():insert(self.db,e)
  self.assertEqual(self.db.execute('SELECT count(*) FROM events').fetchone()[0],3)
  self.assertEqual(self.db.execute('PRAGMA quick_check').fetchone()[0],'ok')
 def test_pending_command_persists_after_termination(self):
  e=BACKUP['events'][2]
  with self.db:self.db.execute('INSERT INTO pending VALUES(1,?)',(json.dumps(e),))
  self.db.close();self.db=sqlite3.connect(self.path)
  pending=json.loads(self.db.execute('SELECT json FROM pending').fetchone()[0]);self.assertEqual(pending['id'],e['id'])
  with self.db:insert(self.db,pending)
  # Simulate a second process death after commit but before acknowledgment.
  self.db.close();self.db=sqlite3.connect(self.path)
  pending=json.loads(self.db.execute('SELECT json FROM pending').fetchone()[0])
  if not self.db.execute('SELECT 1 FROM events WHERE id=?',(pending['id'],)).fetchone():
   with self.db:insert(self.db,pending)
  with self.db:self.db.execute('DELETE FROM pending')
  self.assertEqual(self.db.execute('SELECT count(*) FROM events').fetchone()[0],3)
 def test_manifest_receipt_picker_has_no_storage_or_camera_permissions(self):
  manifest=ET.parse(ROOT/'app/src/main/AndroidManifest.xml').getroot()
  permissions={p.get('{http://schemas.android.com/apk/res/android}name') for p in manifest.findall('uses-permission')}
  self.assertIn('android.permission.INTERNET',permissions)
  self.assertIn('android.permission.CAMERA',permissions)
  self.assertNotIn('android.permission.READ_EXTERNAL_STORAGE',permissions)
  ns='{http://schemas.android.com/apk/res/android}'
  self.assertEqual(manifest.find('application').get(ns+'allowBackup'),'false')
MIGRATION=(ROOT/'app/src/main/assets/migration-3.sql').read_text()
class MigrationTests(LocalDatabaseTests):
 def setUp(self):
  super().setUp();self.original=list(self.db.execute('SELECT * FROM events'))
  self.db.executescript('BEGIN;'+MIGRATION+'PRAGMA user_version=3;COMMIT;')
 def test_migration_preserves_every_legacy_row(self):
  self.assertEqual(list(self.db.execute('SELECT * FROM events')),self.original)
  self.assertEqual(self.db.execute('SELECT count(*) FROM audit').fetchone()[0],2)
  self.assertEqual(self.db.execute('SELECT count(*) FROM audit WHERE occurred_at IS NULL').fetchone()[0],2)
 def test_new_sale_audited_atomically_and_history_immutable(self):
  with self.db:insert(self.db,BACKUP['events'][2])
  self.assertEqual(self.db.execute('SELECT count(*) FROM audit').fetchone()[0],3)
  with self.assertRaises(sqlite3.IntegrityError):self.db.execute('DELETE FROM audit')
 def test_document_deduplication_does_not_add_stock(self):
  original=b'%PDF-test original';digest=__import__('hashlib').sha256(original).hexdigest()
  with self.db:
   self.db.execute('INSERT INTO supplier_receipts VALUES(?,?,?)',(digest,'application/pdf',original))
   self.db.execute('INSERT INTO documents VALUES(?,?,?,?,?)',('supplier-doc01','purchase',digest,'supplier-invoice-001','{}'))
  with self.assertRaises(sqlite3.IntegrityError):
   with self.db:self.db.execute('INSERT INTO documents VALUES(?,?,?,?,?)',('supplier-doc02','purchase',digest,'supplier-invoice-002','{}'))
  self.assertEqual(self.db.execute('SELECT count(*) FROM events').fetchone()[0],2)
 def test_delivery_commit_failure_rolls_back_stock_and_audit(self):
  before=self.db.execute('SELECT count(*) FROM audit').fetchone()[0]
  with self.assertRaises(sqlite3.IntegrityError):
   with self.db:
    insert(self.db,BACKUP['events'][2])
    self.db.execute('INSERT INTO deliveries VALUES(?,?,?,?)',('delivery-00001','missing-line',BACKUP['events'][2]['id'],'{}'))
  self.assertEqual(self.db.execute('SELECT count(*) FROM audit').fetchone()[0],before)
  self.assertEqual(self.db.execute('SELECT count(*) FROM events').fetchone()[0],2)
 def test_reopen_version_does_not_reseed(self):
  self.db.close();self.db=sqlite3.connect(self.path)
  self.assertEqual(self.db.execute('PRAGMA user_version').fetchone()[0],3)
  self.assertEqual(self.db.execute('SELECT count(*) FROM events').fetchone()[0],2)
 def test_receipt_bytes_immutable_and_retained(self):
  data=b'%PDF-original bytes';digest=__import__('hashlib').sha256(data).hexdigest()
  with self.db:self.db.execute('INSERT INTO supplier_receipts VALUES(?,?,?)',(digest,'application/pdf',data))
  with self.assertRaises(sqlite3.IntegrityError):self.db.execute('UPDATE supplier_receipts SET content=?',(b'changed',))
  self.assertEqual(self.db.execute('SELECT content FROM supplier_receipts').fetchone()[0],data)
class CatalogMigrationTests(unittest.TestCase):
 def setUp(self):
  self.fixture=MigrationTests();self.fixture.setUp();self.db=self.fixture.db
  self.before=list(self.db.execute('SELECT * FROM events'));self.audit=list(self.db.execute('SELECT * FROM audit'))
  self.db.executescript('BEGIN;'+(ROOT/'app/src/main/assets/migration-4.sql').read_text()+'PRAGMA user_version=4;COMMIT;')
 def tearDown(self):self.fixture.tearDown()
 def test_catalog_migration_preserves_ledger_audit_dates_and_settings(self):
  self.assertEqual(list(self.db.execute('SELECT * FROM events')),self.before)
  self.assertEqual(list(self.db.execute('SELECT * FROM audit')),self.audit)
  self.assertEqual(self.db.execute('SELECT id FROM products').fetchone()[0],'legacy-unassigned')
  self.assertEqual(self.db.execute('PRAGMA quick_check').fetchone()[0],'ok')
 def test_historical_flavours_and_transfers_are_append_only(self):
  with self.db:self.db.execute('INSERT INTO event_products VALUES(?,?,?)',(self.before[0][1],'legacy-unassigned',24))
  with self.assertRaises(sqlite3.IntegrityError):self.db.execute('UPDATE event_products SET quantity=1')
  with self.assertRaises(sqlite3.IntegrityError):self.db.execute('DELETE FROM event_products')
  with self.db:self.db.execute('INSERT INTO flavour_transfers VALUES(?,?)',('transfer-test01','{}'))
  with self.assertRaises(sqlite3.IntegrityError):self.db.execute('DELETE FROM flavour_transfers')
 def test_barcode_association_rejects_unknown_product(self):
  with self.assertRaises(sqlite3.IntegrityError):
   with self.db:self.db.execute('INSERT INTO barcodes VALUES(?,?)',('0012345678905','unknown-product'))
  self.assertEqual(self.db.execute('SELECT count(*) FROM barcodes').fetchone()[0],0)
class FinanceMigrationTests(unittest.TestCase):
 def setUp(self):
  self.fixture=CatalogMigrationTests();self.fixture.setUp();self.db=self.fixture.db
  self.before=list(self.db.execute('SELECT * FROM events'));self.audit=list(self.db.execute('SELECT * FROM audit'))
  self.db.executescript('BEGIN;'+(ROOT/'app/src/main/assets/migration-5.sql').read_text()+'PRAGMA user_version=5;COMMIT;')
 def tearDown(self):self.fixture.tearDown()
 def test_finance_migration_preserves_history_and_defaults_unregistered(self):
  self.assertEqual(list(self.db.execute('SELECT * FROM events')),self.before)
  self.assertEqual(list(self.db.execute('SELECT * FROM audit')),self.audit)
  self.assertFalse(json.loads(self.db.execute("SELECT body FROM finance_settings WHERE key='gst'").fetchone()[0])['registered'])
 def test_historical_tax_snapshot_cannot_be_rewritten(self):
  with self.db:self.db.execute('INSERT INTO finance_tax VALUES(?,?,?)',('tax-test-001','ledger','{}'))
  with self.assertRaises(sqlite3.IntegrityError):self.db.execute("UPDATE finance_tax SET body='changed'")
  with self.assertRaises(sqlite3.IntegrityError):self.db.execute('DELETE FROM finance_tax')
if __name__=='__main__':unittest.main(verbosity=2)
