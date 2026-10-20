package au.monster.tracker;

import android.content.ContentValues;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import java.util.List;

/** Persistent proceeds balances. All values are AUD cents and updates share the sale transaction. */
public final class FundsStore {
    private static final String CASH = "funds_cash";
    private static final String CARD = "funds_card";

    private FundsStore() {}

    /** Backfill existing installs once from their recorded sales; never reset an existing balance. */
    static void ensure(SQLiteDatabase db, List<Ledger.Event> events) {
        if (!has(db, CASH) || !has(db, CARD)) {
            Ledger.Totals totals = Ledger.totals(events);
            if (!has(db, CASH)) put(db, CASH, totals.cash());
            if (!has(db, CARD)) put(db, CARD, totals.card());
        }
    }

    public static long balance(SQLiteDatabase db, String payment) {
        String key = key(payment);
        try (Cursor c = db.rawQuery("SELECT value FROM settings WHERE key=?", new String[]{key})) {
            return c.moveToFirst() ? c.getLong(0) : 0L;
        }
    }

    /** Called inside Store's existing SQLite transaction, so a sale and its funds update cannot split. */
    static void apply(SQLiteDatabase db, Ledger.Event event) {
        if (event.type().equals("single") || event.type().equals("deal")) {
            adjust(db, event.payment(), event.revenue());
        } else if (event.type().equals("undo")) {
            try (Cursor c = db.rawQuery("SELECT type,payment,revenue FROM events WHERE id=?",
                    new String[]{event.target()})) {
                if (c.moveToFirst()) {
                    String type = c.getString(0);
                    if (type.equals("single") || type.equals("deal")) {
                        adjust(db, c.getString(1), -c.getLong(2));
                    }
                }
            }
        }
    }

    private static void adjust(SQLiteDatabase db, String payment, long delta) {
        String key = key(payment);
        long current = balance(db, payment);
        long next = current + delta;
        if (next < 0 || next > Ledger.MAX_MONEY) {
            throw new IllegalArgumentException("Funds balance would be outside $0–$100,000. Recount funds before correcting this sale.");
        }
        put(db, key, next);
    }

    private static String key(String payment) {
        if ("cash".equals(payment)) return CASH;
        if ("card".equals(payment)) return CARD;
        throw new IllegalArgumentException("Funds account must be cash or card.");
    }

    private static boolean has(SQLiteDatabase db, String key) {
        try (Cursor c = db.rawQuery("SELECT 1 FROM settings WHERE key=?", new String[]{key})) {
            return c.moveToFirst();
        }
    }

    private static void put(SQLiteDatabase db, String key, long cents) {
        Ledger.checkMoney(cents);
        ContentValues values = new ContentValues();
        values.put("key", key);
        values.put("value", cents);
        db.insertWithOnConflict("settings", null, values, SQLiteDatabase.CONFLICT_REPLACE);
    }
}
