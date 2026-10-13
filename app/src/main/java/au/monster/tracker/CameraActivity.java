package au.monster.tracker;

import android.app.*;
import android.os.Bundle;
import android.Manifest;
import android.content.*;
import android.content.pm.PackageManager;
import android.graphics.ImageFormat;
import android.hardware.Camera;
import android.net.Uri;
import android.view.*;
import android.widget.*;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.barcode.*;
import com.google.mlkit.vision.barcode.common.Barcode;
import java.io.*;
import java.util.*;

/** Offline live camera: full-resolution receipt capture or bundled retail-barcode scanning. */
@SuppressWarnings("deprecation")
public final class CameraActivity extends Activity implements SurfaceHolder.Callback {
    private Camera camera;private SurfaceView preview;private TextView status;private BarcodeScanner scanner;private boolean inflight,done,surfaceReady;private int rotation;private String mode;
    @Override public void onCreate(Bundle b){super.onCreate(b);mode=getIntent().getStringExtra("mode");if(mode==null)mode="barcode";LinearLayout root=new LinearLayout(this);root.setOrientation(1);root.setBackgroundColor(0xff101410);root.setPadding(16,24,16,24);root.setOnApplyWindowInsetsListener((v,insets)->{root.setPadding(16,insets.getSystemWindowInsetTop()+8,16,insets.getSystemWindowInsetBottom()+8);return insets;});setContentView(root);root.requestApplyInsets();status=new TextView(this);status.setTextColor(0xfff0f5eb);status.setTextSize(18);status.setText(mode.equals("receipt")?"Live receipt photo · tap preview to focus":"Align the barcode · scanning entirely on this phone");root.addView(status);preview=new SurfaceView(this);root.addView(preview,new LinearLayout.LayoutParams(-1,0,1));preview.getHolder().addCallback(this);preview.setOnClickListener(v->{if(camera!=null)try{camera.autoFocus((ok,c)->{});}catch(RuntimeException ignored){}});
        if(mode.equals("receipt")){Button capture=new Button(this);capture.setText("Take receipt photo");capture.setMinHeight(64);capture.setOnClickListener(v->capture(capture));root.addView(capture);}else scanner=BarcodeScanning.getClient(new BarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_EAN_13,Barcode.FORMAT_EAN_8,Barcode.FORMAT_UPC_A,Barcode.FORMAT_UPC_E,Barcode.FORMAT_CODE_128).build());
        Button cancel=new Button(this);cancel.setText("Cancel / enter manually");cancel.setMinHeight(56);cancel.setOnClickListener(v->{done=true;finish();});root.addView(cancel);
        if(checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED)requestPermissions(new String[]{Manifest.permission.CAMERA},61);
    }
    @Override public void onRequestPermissionsResult(int r,String[] p,int[] grants){super.onRequestPermissionsResult(r,p,grants);if(r==61){if(grants.length>0&&grants[0]==PackageManager.PERMISSION_GRANTED)open();else status.setText("Camera permission declined. Cancel and use manual entry or import a receipt.");}}
    @Override public void surfaceCreated(SurfaceHolder h){surfaceReady=true;open();}
    @Override public void surfaceChanged(SurfaceHolder h,int f,int w,int height){}
    @Override public void surfaceDestroyed(SurfaceHolder h){surfaceReady=false;release();}
    @Override protected void onResume(){super.onResume();if(surfaceReady)open();}
    @Override protected void onPause(){release();super.onPause();}
    @Override protected void onDestroy(){done=true;release();if(scanner!=null)scanner.close();super.onDestroy();}
    private void open(){if(camera!=null||!surfaceReady||checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED)return;try{int index=0;Camera.CameraInfo info=new Camera.CameraInfo();for(int i=0;i<Camera.getNumberOfCameras();i++){Camera.getCameraInfo(i,info);if(info.facing==Camera.CameraInfo.CAMERA_FACING_BACK){index=i;break;}}Camera.getCameraInfo(index,info);camera=Camera.open(index);Camera.Parameters parameters=camera.getParameters();Camera.Size previewSize=parameters.getSupportedPreviewSizes().get(0);long distance=Long.MAX_VALUE;for(Camera.Size s:parameters.getSupportedPreviewSizes()){long d=Math.abs((long)s.width*s.height-1280L*720);if(d<distance){distance=d;previewSize=s;}}parameters.setPreviewSize(previewSize.width,previewSize.height);parameters.setPreviewFormat(ImageFormat.NV21);List<String> focuses=parameters.getSupportedFocusModes();if(focuses!=null&&focuses.contains(Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE))parameters.setFocusMode(Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE);int degrees=getWindowManager().getDefaultDisplay().getRotation()*90;rotation=(info.orientation-degrees+360)%360;parameters.setRotation(rotation);parameters.setJpegQuality(90);Camera.Size chosen=null;for(Camera.Size s:parameters.getSupportedPictureSizes())if((long)s.width*s.height<=8000000L&&(chosen==null||(long)s.width*s.height>(long)chosen.width*chosen.height))chosen=s;if(chosen!=null)parameters.setPictureSize(chosen.width,chosen.height);camera.setParameters(parameters);camera.setDisplayOrientation(rotation);camera.setPreviewDisplay(preview.getHolder());if(scanner!=null)camera.setPreviewCallback((bytes,c)->scan(bytes,c));camera.startPreview();}catch(Exception e){release();status.setText("Camera unavailable. Cancel and use manual entry / import. "+e.getMessage());}}
    private void scan(byte[] bytes,Camera c){if(inflight||done)return;inflight=true;Camera.Size size=c.getParameters().getPreviewSize();InputImage image=InputImage.fromByteArray(bytes.clone(),size.width,size.height,rotation,InputImage.IMAGE_FORMAT_NV21);scanner.process(image).addOnSuccessListener(codes->{if(done)return;for(Barcode barcode:codes){String value=barcode.getRawValue();if(value!=null&&!value.trim().isEmpty()){done=true;setResult(RESULT_OK,new Intent().putExtra("barcode",value));finish();break;}}}).addOnFailureListener(e->{if(!done)status.setText("Try closer / steadier, or cancel for manual entry.");}).addOnCompleteListener(task->inflight=false);}
    private void capture(Button button){if(camera==null||done)return;button.setEnabled(false);try{camera.takePicture(null,null,(bytes,c)->{try{if(bytes.length>Purchases.MAX_RECEIPT)throw new IOException("Photo exceeds 16 MB. Import a smaller image.");File dir=new File(getCacheDir(),"receipt-camera");dir.mkdirs();String file=Ledger.id()+".jpg";try(OutputStream out=new FileOutputStream(new File(dir,file))){out.write(bytes);}Uri uri=Uri.parse("content://"+getPackageName()+".receipts/camera/"+file);done=true;setResult(RESULT_OK,new Intent().setData(uri));finish();}catch(Exception e){status.setText("Photo not saved: "+e.getMessage());button.setEnabled(true);try{c.startPreview();}catch(RuntimeException ignored){}}});}catch(RuntimeException e){button.setEnabled(true);status.setText("Capture failed. Try again or import a photo.");}}
    private void release(){if(camera!=null){try{camera.setPreviewCallback(null);camera.stopPreview();}catch(RuntimeException ignored){}camera.release();camera=null;}}
}
