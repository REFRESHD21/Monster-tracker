#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/core
# This environment provides jdk.compiler even when the javac launcher is absent.
java -m jdk.compiler/com.sun.tools.javac.Main -source 17 -target 17 -d .build/core \
 app/src/main/java/au/monster/tracker/Ledger.java \
 app/src/main/java/au/monster/tracker/Json.java \
 app/src/main/java/au/monster/tracker/Backup.java \
 app/src/main/java/au/monster/tracker/Receipts.java \
 app/src/main/java/au/monster/tracker/Purchases.java \
 app/src/main/java/au/monster/tracker/BusinessBackup.java \
 app/src/main/java/au/monster/tracker/Catalog.java \
 app/src/main/java/au/monster/tracker/CatalogBackup.java \
 app/src/main/java/au/monster/tracker/ReceiptParser.java \
 app/src/test/java/au/monster/tracker/CoreTests.java \
 app/src/test/java/au/monster/tracker/PurchaseTests.java \
 app/src/test/java/au/monster/tracker/CatalogTests.java
java -cp .build/core au.monster.tracker.CoreTests
java -cp .build/core au.monster.tracker.PurchaseTests
java -cp .build/core au.monster.tracker.CatalogTests
python3 scripts/test-sqlite.py
if command -v node >/dev/null 2>&1; then node scripts/test-parity.mjs; else echo 'Legacy parity check not run: Node unavailable.'; fi
