package au.monster.tracker;

import android.app.*;
import android.os.Bundle;
import android.content.Context;
import android.content.pm.PackageInfo;
import java.util.*;

/** Dependency-free device tests of the production Store, using isolated database files. */
public final class DatabaseTestRunner extends Instrumentation {
    private int total=9,index=0,passed=0,failed=0;
    interface Case {void run()throws Exception;}
    @Override public void onCreate(Bundle args){super.onCreate(args);start();}
    private void eq(Object a,Object b){if(!Objects.equals(a,b))throw new AssertionError("got="+a+", expected="+b);}
    private void check(boolean condition){if(!condition)throw new AssertionError("Condition failed");}
    private Ledger.Event sale(){long now=System.currentTimeMillis();return new Ledger.Event(Ledger.id(),now,now,"deal",2,"card",600,25,0,"device test",null);}
    private void test(String name,Case fn){index++;Bundle b=new Bundle();b.putString("class",getClass().getName());b.putString("test",name);b.putInt("numtests",total);b.putInt("current",index);sendStatus(1,b);try{fn.run();passed++;b.putString("stream","PASS "+name+"\n");sendStatus(0,b);}catch(Throwable e){failed++;b.putString("stream","FAIL "+name+": "+e+"\n");b.putString("stack",android.util.Log.getStackTraceString(e));sendStatus(-2,b);}}
    interface WithStore {void run(Store store,String filename)throws Exception;}
    private void fresh(WithStore fn)throws Exception{Context c=getTargetContext();String file="test-"+UUID.randomUUID()+".db";Store s=new Store(c,file);try{fn.run(s,file);}finally{s.close();c.deleteDatabase(file);}}
    @Override public void onStart(){
        test("firstLaunchOfflineOpeningExactlyOnce",()->fresh((s,file)->{eq(s.snapshot().totals().stock(),20L);eq(s.snapshot().totals().purchases(),5000L);eq(s.snapshot().totals().result(),-5000L);eq(s.snapshot().events().get(1).timestamp(),null);s.close();try(Store reopened=new Store(getTargetContext(),file)){eq(reopened.snapshot().events().size(),2);eq(reopened.snapshot().totals().stock(),20L);}}));
        test("cashCardDealsAndPersistentRestart",()->fresh((s,file)->{s.record(sale());eq(s.snapshot().totals().stock(),18L);eq(s.snapshot().totals().card(),600L);eq(s.snapshot().totals().fees(),25L);s.close();try(Store again=new Store(getTargetContext(),file)){eq(again.snapshot().events().size(),3);eq(again.snapshot().totals().result(),-4425L);}}));
        test("sameIdIsIdempotent",()->fresh((s,file)->{var e=sale();check(s.record(e));check(!s.record(e));eq(s.snapshot().events().size(),3);}));
        test("pendingSaveRecoveryBeforeAndAfterCommit",()->fresh((s,file)->{var e=sale();s.stage(e);s.close();try(Store afterCrash=new Store(getTargetContext(),file)){afterCrash.recoverPending();eq(afterCrash.snapshot().events().size(),3);}try(Store secondCrash=new Store(getTargetContext(),file)){secondCrash.recoverPending();eq(secondCrash.snapshot().events().size(),3);secondCrash.acknowledge(e.id());eq(secondCrash.recoverPending(),null);}}));
        test("undoAndStockLimits",()->fresh((s,file)->{var e=sale();s.record(e);s.record(Ledger.event("undo",0,"none",0,0,0,"Mistaken entry",System.currentTimeMillis(),e.id()));eq(s.snapshot().totals().stock(),20L);try{s.record(Ledger.event("missing",21,"none",0,0,0,"",System.currentTimeMillis(),null));throw new AssertionError("Oversale accepted");}catch(IllegalArgumentException expected){}eq(s.snapshot().events().size(),4);}));
        test("backupRestoreMergeAndSettings",()->fresh((s,file)->{s.record(sale());s.setPrices(new Ledger.Prices(400,700));var before=s.snapshot();var data=Backup.decode(Backup.encode(new Backup.Data(before.events(),before.prices())));String other="restore-"+UUID.randomUUID()+".db";try(Store replacement=new Store(getTargetContext(),other)){eq(replacement.importBackup(data),1);eq(replacement.importBackup(data),0);eq(replacement.snapshot().totals().stock(),18L);eq(replacement.snapshot().prices().single(),400L);}finally{getTargetContext().deleteDatabase(other);}}));
        test("conflictingRestoreIsTransactional",()->fresh((s,file)->{var e=sale();s.record(e);var es=new ArrayList<>(s.snapshot().events());es.set(2,new Ledger.Event(e.id(),e.timestamp(),e.recordedAt(),e.type(),e.quantity(),e.payment(),650,e.fee(),e.cost(),e.note(),e.target()));try{s.importBackup(new Backup.Data(es,new Ledger.Prices(999,999)));throw new AssertionError("Conflict accepted");}catch(IllegalArgumentException expected){}eq(s.snapshot().events().size(),3);eq(s.snapshot().prices().single(),350L);}));
        test("corruptBackupRejectedWithoutWrites",()->fresh((s,file)->{String text=Backup.encode(new Backup.Data(s.snapshot().events(),s.snapshot().prices()));try{s.importBackup(Backup.decode(text.substring(0,text.length()/2)));throw new AssertionError("Corrupt file accepted");}catch(IllegalArgumentException expected){}eq(s.snapshot().events().size(),2);}));
        test("noInternetPermissionOrRemoteAuthentication",()->{PackageInfo info=getTargetContext().getPackageManager().getPackageInfo(getTargetContext().getPackageName(),android.content.pm.PackageManager.GET_PERMISSIONS);if(info.requestedPermissions!=null)for(String p:info.requestedPermissions)check(!p.equals("android.permission.INTERNET"));check(getTargetContext().getAssets().open("schema.sql")!=null);});
        Bundle done=new Bundle();done.putString("stream","\nDEVICE RESULTS: "+passed+" passed, "+failed+" failed.\n");finish(failed==0?Activity.RESULT_OK:Activity.RESULT_CANCELED,done);
    }
}
