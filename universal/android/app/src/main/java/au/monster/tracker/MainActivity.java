package au.monster.tracker;
import android.os.Bundle;
import android.content.Intent;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import java.util.concurrent.Executors;

/** Export through the original validators; never open/create a legacy DB on a new install. */
public final class MainActivity extends FlutterActivity {
 @Override public void configureFlutterEngine(FlutterEngine engine) {
  super.configureFlutterEngine(engine);
  new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"au.monster.tracker.plus/migration").setMethodCallHandler((call,result)->{
   if(!call.method.equals("legacyBackup")){result.notImplemented();return;}
   if(!getDatabasePath("monster-offline.db").isFile()){result.success(null);return;}
   var executor=Executors.newSingleThreadExecutor();executor.execute(()->{
    try(Store store=new Store(this)){
     if(store.checkout()!=null)throw new IllegalStateException("Unresolved legacy card payment. Keep the existing database and resolve it before migration; no payment processing is enabled here.");
     String json=Backup.encode(store.fullBackup());Backup.decode(json);
     java.io.File safety=new java.io.File(getFilesDir(),"pre-flutter-migration.json");
     if(!safety.exists()){try(var out=new java.io.FileOutputStream(safety)){out.write(json.getBytes(java.nio.charset.StandardCharsets.UTF_8));out.getFD().sync();}}
     runOnUiThread(()->result.success(json));
    }catch(Exception e){runOnUiThread(()->result.error("MIGRATION_BLOCKED",e.getMessage(),null));}finally{executor.shutdown();}
   });
  });
 }
}
