package au.monster.tracker.backup;
import android.app.Activity;
import android.content.*;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.provider.DocumentsContract;
import java.io.*;
import java.util.concurrent.Executors;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.*;
import io.flutter.plugin.common.*;

/** SAF grants remain user-selected; plugin registration also works in background engines. */
public final class BackupDestinationPlugin implements FlutterPlugin, ActivityAware, PluginRegistry.ActivityResultListener {
 private Context context;private Activity activity;private ActivityPluginBinding binding;
 private MethodChannel channel;private MethodChannel.Result pending;
 private static final int REQUEST=8419;
 @Override public void onAttachedToEngine(FlutterPluginBinding b){context=b.getApplicationContext();channel=new MethodChannel(b.getBinaryMessenger(),"au.monster.tracker.plus/backup-destination");channel.setMethodCallHandler((call,result)->{
  if(call.method.equals("chooseFolder")){
   if(activity==null || pending!=null){result.error("PICKER_UNAVAILABLE","Open settings on screen before choosing a folder.",null);return;}
   pending=result;Intent i=new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION|Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION|Intent.FLAG_GRANT_PREFIX_URI_PERMISSION);activity.startActivityForResult(i,REQUEST);
  }else if(call.method.equals("writeBackup")){
   var executor=Executors.newSingleThreadExecutor();executor.execute(()->{
    Uri destination=null;boolean complete=false;
    try {
     String folder=call.argument("folder"),name=call.argument("name");byte[] bytes=call.argument("bytes");
     if(folder==null||name==null||!name.matches("[A-Za-z0-9.-]{1,160}")||bytes==null||bytes.length>64*1024*1024+1024)throw new IOException("Invalid backup copy.");
     Uri tree=Uri.parse(folder);if(!"content".equals(tree.getScheme()))throw new IOException("Select a document-provider folder.");
     Uri parent=DocumentsContract.buildDocumentUriUsingTree(tree,DocumentsContract.getTreeDocumentId(tree));destination=DocumentsContract.createDocument(context.getContentResolver(),parent,"application/octet-stream",name);if(destination==null)throw new IOException("Provider did not create the backup.");
     try(OutputStream out=context.getContentResolver().openOutputStream(destination,"w")){if(out==null)throw new IOException("Folder is not writable.");out.write(bytes);out.flush();}
     byte[] readback;try(InputStream in=context.getContentResolver().openInputStream(destination);ByteArrayOutputStream out=new ByteArrayOutputStream()) {if(in==null)throw new IOException("Cannot verify provider backup.");byte[] chunk=new byte[65536];int n;while((n=in.read(chunk))!=-1){if(out.size()+n>bytes.length)throw new IOException("Provider backup changed size.");out.write(chunk,0,n);}readback=out.toByteArray();}
     if(!java.security.MessageDigest.isEqual(bytes,readback))throw new IOException("Provider backup failed verification. Local recovery is retained.");complete=true;
     new Handler(Looper.getMainLooper()).post(()->result.success(null));
    }catch(Exception e){new Handler(Looper.getMainLooper()).post(()->result.error("BACKUP_COPY_FAILED",e.getMessage(),null));}
    finally {if(!complete && destination!=null)try{DocumentsContract.deleteDocument(context.getContentResolver(),destination);}catch(Exception ignored){}executor.shutdown();}
   });
  }else result.notImplemented();
 });}
 @Override public boolean onActivityResult(int request,int result,Intent data){if(request!=REQUEST||pending==null)return false;var response=pending;pending=null;if(result!=Activity.RESULT_OK||data==null||data.getData()==null){response.success(null);return true;}try{Uri uri=data.getData();int flags=data.getFlags()&(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION);context.getContentResolver().takePersistableUriPermission(uri,flags);response.success(uri.toString());}catch(Exception e){response.error("FOLDER_PERMISSION",e.getMessage(),null);}return true;}
 @Override public void onAttachedToActivity(ActivityPluginBinding b){binding=b;activity=b.getActivity();b.addActivityResultListener(this);}
 @Override public void onDetachedFromActivityForConfigChanges(){detach();}
 @Override public void onReattachedToActivityForConfigChanges(ActivityPluginBinding b){onAttachedToActivity(b);}
 @Override public void onDetachedFromActivity(){detach();if(pending!=null){pending.error("PICKER_CLOSED","Folder selection interrupted.",null);pending=null;}}
 private void detach(){if(binding!=null)binding.removeActivityResultListener(this);binding=null;activity=null;}
 @Override public void onDetachedFromEngine(FlutterPluginBinding b){channel.setMethodCallHandler(null);}
}
