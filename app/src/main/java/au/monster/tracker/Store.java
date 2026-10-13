package au.monster.tracker;

import android.content.*;
import android.database.Cursor;
import android.database.sqlite.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** All business writes are atomic SQLite transactions; history is append-only at the database level. */
public final class Store implements AutoCloseable {
    private final Helper helper;
    public record Snapshot(List<Ledger.Event> events,Ledger.Prices prices,Ledger.Totals totals) {}
    public Store(Context context){this(context,"monster-offline.db");}
    Store(Context context,String name){helper=new Helper(context.getApplicationContext(),name);helper.setWriteAheadLoggingEnabled(true);}
    private static final class Helper extends SQLiteOpenHelper {
        final Context context;
        Helper(Context c,String name){super(c,name,null,1);context=c;}
        @Override public void onConfigure(SQLiteDatabase db){db.setForeignKeyConstraintsEnabled(true);}
        @Override public void onCreate(SQLiteDatabase db){
            try(BufferedReader r=new BufferedReader(new InputStreamReader(context.getAssets().open("schema.sql"),StandardCharsets.UTF_8))){
                String line;StringBuilder statement=new StringBuilder();while((line=r.readLine())!=null){statement.append(line).append('\n');if(line.trim().endsWith(";")){db.execSQL(statement.toString());statement.setLength(0);}}
            }catch(IOException ex){throw new IllegalStateException("Could not create local database.",ex);}
            // SQLiteOpenHelper invokes onCreate inside a transaction. Never seed on every launch.
            for(var e:Ledger.opening(System.currentTimeMillis()))insert(db,e);
            price(db,"single",350);price(db,"deal",600);
        }
        @Override public void onUpgrade(SQLiteDatabase db,int oldVersion,int newVersion){throw new IllegalStateException("A non-destructive migration is required. No records were deleted.");}
        @Override public void onOpen(SQLiteDatabase db){super.onOpen(db);try(Cursor c=db.rawQuery("PRAGMA quick_check",null)){if(!c.moveToFirst()||!c.getString(0).equals("ok"))throw new IllegalStateException("Local database integrity check failed. Do not uninstall; keep backups and request recovery help.");}}
    }
    private static void price(SQLiteDatabase db,String key,long value){ContentValues v=new ContentValues();v.put("key",key);v.put("value",value);db.insertWithOnConflict("settings",null,v,SQLiteDatabase.CONFLICT_REPLACE);}
    private static void insert(SQLiteDatabase db,Ledger.Event e){ContentValues v=new ContentValues();v.put("id",e.id());if(e.timestamp()==null)v.putNull("timestamp");else v.put("timestamp",e.timestamp());v.put("recorded_at",e.recordedAt());v.put("type",e.type());v.put("quantity",e.quantity());v.put("payment",e.payment());v.put("revenue",e.revenue());v.put("fee",e.fee());v.put("cost",e.cost());v.put("note",e.note());if(e.target()==null)v.putNull("target");else v.put("target",e.target());db.insertOrThrow("events",null,v);}
    private static List<Ledger.Event> events(SQLiteDatabase db){ArrayList<Ledger.Event> out=new ArrayList<>();try(Cursor c=db.rawQuery("SELECT id,timestamp,recorded_at,type,quantity,payment,revenue,fee,cost,note,target FROM events ORDER BY seq",null)){while(c.moveToNext())out.add(new Ledger.Event(c.getString(0),c.isNull(1)?null:c.getLong(1),c.getLong(2),c.getString(3),c.getLong(4),c.getString(5),c.getLong(6),c.getLong(7),c.getLong(8),c.getString(9),c.isNull(10)?null:c.getString(10)));}return Ledger.copy(out);}
    private static Ledger.Prices prices(SQLiteDatabase db){Map<String,Long> p=new HashMap<>();try(Cursor c=db.rawQuery("SELECT key,value FROM settings",null)){while(c.moveToNext())p.put(c.getString(0),c.getLong(1));}if(!p.containsKey("single")||!p.containsKey("deal"))throw new IllegalStateException("Price settings are missing; database was not reset.");return new Ledger.Prices(p.get("single"),p.get("deal"));}
    public synchronized Snapshot snapshot(){SQLiteDatabase db=helper.getWritableDatabase();db.beginTransaction();try{var list=events(db);var result=new Snapshot(list,prices(db),Ledger.totals(list));db.setTransactionSuccessful();return result;}finally{db.endTransaction();}}
    public synchronized void setPrices(Ledger.Prices p){SQLiteDatabase db=helper.getWritableDatabase();db.beginTransaction();try{price(db,"single",p.single());price(db,"deal",p.deal());db.setTransactionSuccessful();}finally{db.endTransaction();}}
    private static boolean append(SQLiteDatabase db,Ledger.Event e){var current=events(db);for(var old:current)if(old.id().equals(e.id())){if(!Ledger.same(old,e))throw new IllegalArgumentException("Transaction ID conflict. No changes saved.");return false;}if(current.size()>=Ledger.MAX_EVENTS)throw new IllegalArgumentException("Transaction limit reached. Export a backup.");Ledger.validate(e,current);insert(db,e);return true;}
    synchronized boolean record(Ledger.Event e){SQLiteDatabase db=helper.getWritableDatabase();db.beginTransaction();try{boolean added=append(db,e);db.setTransactionSuccessful();return added;}finally{db.endTransaction();}}
    public synchronized void stage(Ledger.Event e){SQLiteDatabase db=helper.getWritableDatabase();db.beginTransaction();try{var old=pending(db);if(old!=null&&!Ledger.same(old,e))throw new IllegalStateException("Another save is pending. Reopen the app to recover it.");var current=events(db);var existing=current.stream().filter(x->x.id().equals(e.id())).findFirst();if(existing.isPresent()){if(!Ledger.same(existing.get(),e))throw new IllegalArgumentException("Transaction ID conflict.");}else Ledger.validate(e,current);ContentValues v=new ContentValues();v.put("id",1);v.put("json",Json.write(Backup.eventMap(e)));db.insertWithOnConflict("pending",null,v,SQLiteDatabase.CONFLICT_REPLACE);db.setTransactionSuccessful();}finally{db.endTransaction();}}
    private static Ledger.Event pending(SQLiteDatabase db){try(Cursor c=db.rawQuery("SELECT json FROM pending WHERE id=1",null)){return c.moveToFirst()?Backup.event(Json.parse(c.getString(0))):null;}}
    public synchronized Ledger.Event recoverPending(){var e=pending(helper.getWritableDatabase());if(e!=null)record(e);return e;}
    public synchronized void acknowledge(String id){SQLiteDatabase db=helper.getWritableDatabase();db.beginTransaction();try{var e=pending(db);if(e!=null&&e.id().equals(id))db.delete("pending","id=1",null);db.setTransactionSuccessful();}finally{db.endTransaction();}}
    public synchronized int importBackup(Backup.Data incoming){SQLiteDatabase db=helper.getWritableDatabase();db.beginTransaction();try{if(pending(db)!=null)throw new IllegalStateException("Finish the pending save before importing.");var current=events(db);var merged=Ledger.merge(current,incoming.events());for(int i=current.size();i<merged.size();i++)insert(db,merged.get(i));price(db,"single",incoming.prices().single());price(db,"deal",incoming.prices().deal());db.setTransactionSuccessful();return merged.size()-current.size();}finally{db.endTransaction();}}
    @Override public synchronized void close(){helper.close();}
}
