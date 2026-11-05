package au.monster.tracker;
import android.os.Bundle;
import android.content.Intent;
import com.google.android.gms.auth.api.identity.AuthorizationRequest;
import com.google.android.gms.auth.api.identity.AuthorizationResult;
import com.google.android.gms.auth.api.identity.Identity;
import com.google.android.gms.auth.api.signin.GoogleSignIn;
import com.google.android.gms.common.api.Scope;
import java.util.Collections;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import java.util.concurrent.Executors;

/** Export through the original validators; never open/create a legacy DB on a new install. */
public final class MainActivity extends FlutterActivity {
 private MethodChannel.Result pickerResult;
 private static final int PICK_SHEET=7139;
 private void finishPicker(AuthorizationResult authorization) {
  if(pickerResult==null)return;
  var result=pickerResult;pickerResult=null;
  var params=authorization.getTokenResponseParams();
  String ids=params==null?null:params.getString("picked_file_ids");
  if(ids==null || !ids.matches("[A-Za-z0-9_-]+")){result.error("PICKER_CANCELLED","No spreadsheet selected.",null);return;}
  result.success(ids);
 }
 @Override protected void onActivityResult(int requestCode,int resultCode,Intent data) {
  super.onActivityResult(requestCode,resultCode,data);
  if(requestCode!=PICK_SHEET || pickerResult==null)return;
  try {finishPicker(Identity.getAuthorizationClient(this).getAuthorizationResultFromIntent(data));}
  catch(Exception e){var result=pickerResult;pickerResult=null;result.error("PICKER_CANCELLED","Spreadsheet selection cancelled or not authorized. Retry while connected.",null);}
 }
 @Override protected void onDestroy(){
  if(pickerResult!=null){pickerResult.error("PICKER_CLOSED","Account connection interrupted. Retry from Settings.",null);pickerResult=null;}
  super.onDestroy();
 }
 @Override public void configureFlutterEngine(FlutterEngine engine) {
  super.configureFlutterEngine(engine);
  new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"au.monster.tracker.plus/sheets-picker").setMethodCallHandler((call,result)->{
   if(!call.method.equals("pick")){result.notImplemented();return;}
   if(pickerResult!=null){result.error("PICKER_BUSY","Spreadsheet selection already open.",null);return;}
   var account=GoogleSignIn.getLastSignedInAccount(this);
   String email=call.argument("email");
   if(account==null || account.getAccount()==null || email==null || !email.equalsIgnoreCase(account.getEmail())){result.error("ACCOUNT_CHANGED","Reconnect your Google account first.",null);return;}
   var request=AuthorizationRequest.builder()
    .setAccount(account.getAccount())
    .setRequestedScopes(Collections.singletonList(new Scope("https://www.googleapis.com/auth/drive.file")))
    .setOptOutIncludingGrantedScopes(true)
    .setPrompt(AuthorizationRequest.Prompt.CONSENT)
    .addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_OAUTH_TRIGGER,"true")
    .addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_MIMETYPES,"application/vnd.google-apps.spreadsheet")
    .addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_ALLOW_MULTIPLE,"false").build();
   pickerResult=result;
   Identity.getAuthorizationClient(this).authorize(request).addOnSuccessListener(authorization->{
    if(pickerResult==null)return;
    if(authorization.hasResolution()){
     try{startIntentSenderForResult(authorization.getPendingIntent().getIntentSender(),PICK_SHEET,null,0,0,0);}
     catch(Exception e){pickerResult=null;result.error("PICKER_FAILED","Could not open Google Picker. Check Google Play services and try again.",null);}
    }else{finishPicker(authorization);}
   }).addOnFailureListener(e->{if(pickerResult!=null){pickerResult=null;result.error("PICKER_FAILED","Google Picker unavailable. Check connection, API setup and Google Play services.",null);}});
  });
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
