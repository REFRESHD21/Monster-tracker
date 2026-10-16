"""Add non-default history to the disposable emulator's 1.6.3 database."""
import sqlite3,sys
with sqlite3.connect(sys.argv[1]) as db:
    assert db.execute('PRAGMA user_version').fetchone()[0]==6
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)')
    sql='INSERT INTO events(id,timestamp,recorded_at,type,quantity,payment,revenue,fee,cost,note,target) VALUES(?,?,?,?,?,?,?,?,?,?,?)'
    db.execute(sql,('upgrade-restock-001',1791979200000,1791979200000,'restock',7,'none',0,0,1234,'Migration test purchase',None))
    db.execute(sql,('upgrade-sale-00001',1791979260000,1791979260000,'deal',2,'cash',777,0,0,'Historical custom sale price',None))
    db.commit()
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)')
    assert db.execute('SELECT COUNT(*) FROM events').fetchone()[0]==4
print('Prepared 1.6.3 upgrade fixture: original records + seven-unit purchase + custom-price sale.')
