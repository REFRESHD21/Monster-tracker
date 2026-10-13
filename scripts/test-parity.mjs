import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {totals} from '../provenance/original-ledger.mjs';
const fixtures=JSON.parse(readFileSync(new URL('../.build/parity.json',import.meta.url),'utf8'));
for(const row of fixtures)assert.deepEqual(totals(row.events),row.totals);
console.log(`PASS native Java totals match the existing tracker in ${fixtures.length} sale/fee/restock/missing/undo scenarios.`);
