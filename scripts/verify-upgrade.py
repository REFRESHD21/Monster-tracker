"""Check the installed 1.6.1 database survived an in-place APK upgrade."""
import sqlite3
import sys

with sqlite3.connect(sys.argv[1]) as db:
    assert db.execute('PRAGMA user_version').fetchone()[0] == 6
    assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    rows = db.execute('SELECT id, timestamp, quantity, cost FROM events ORDER BY seq').fetchall()
    assert len(rows) == 2, rows
    assert rows[0] == ('opening-purchase-v1', None, 24, 5000), rows
    assert rows[1] == ('opening-missing-v1', None, 4, 0), rows
    print('PASS: 1.6.1 database retained after in-place update; schema 6 and original records intact.')
