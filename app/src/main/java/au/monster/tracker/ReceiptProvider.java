package au.monster.tracker;

import android.content.*;
import android.database.*;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import java.io.*;

/** URI grants expose only a chosen camera file or original receipt, never the database. */
public final class ReceiptProvider extends ContentProvider {
    @Override public boolean onCreate(){return true;}
    private File camera(Uri uri)throws FileNotFoundException{String name=uri.getLastPathSegment();if(!"camera".equals(uri.getPathSegments().get(0))||name==null||!name.matches("[a-f0-9-]{36}\\.jpg"))throw new FileNotFoundException("Invalid camera path");File dir=new File(getContext().getCacheDir(),"receipt-camera");if(!dir.exists()&&!dir.mkdirs())throw new FileNotFoundException("Camera storage unavailable");return new File(dir,name);}
    private String hash(Uri uri)throws FileNotFoundException{String hash=uri.getLastPathSegment();if(uri.getPathSegments().size()!=2||!"original".equals(uri.getPathSegments().get(0))||hash==null||!hash.matches("[a-f0-9]{64}"))throw new FileNotFoundException("Invalid receipt path");return hash;}
    @Override public ParcelFileDescriptor openFile(Uri uri,String mode)throws FileNotFoundException{if(uri.getPathSegments().size()!=2)throw new FileNotFoundException("Invalid receipt URI");if("camera".equals(uri.getPathSegments().get(0)))return ParcelFileDescriptor.open(camera(uri),ParcelFileDescriptor.parseMode(mode));if(!mode.equals("r"))throw new FileNotFoundException("Original receipts are read-only");String hash=hash(uri);try(Store s=new Store(getContext())){var receipt=new BusinessStore(s).original(hash);File dir=new File(getContext().getCacheDir(),"receipt-view");dir.mkdirs();File file=new File(dir,hash);try(FileOutputStream out=new FileOutputStream(file)){out.write(receipt.content());}return ParcelFileDescriptor.open(file,ParcelFileDescriptor.MODE_READ_ONLY);}catch(Exception e){throw new FileNotFoundException(e.getMessage());}}
    @Override public String getType(Uri uri){if(uri.getPathSegments().size()==2&&"camera".equals(uri.getPathSegments().get(0)))return "image/jpeg";try(Store s=new Store(getContext())){return new BusinessStore(s).receiptMime(hash(uri));}catch(Exception e){return "application/octet-stream";}}
    @Override public Cursor query(Uri uri,String[] projection,String selection,String[] args,String sort){MatrixCursor c=new MatrixCursor(new String[]{OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE});c.addRow(new Object[]{"receipt-"+uri.getLastPathSegment(),null});return c;}
    @Override public Uri insert(Uri u,ContentValues v){throw new UnsupportedOperationException("Use the purchase review screen");}
    @Override public int update(Uri u,ContentValues v,String s,String[] a){throw new UnsupportedOperationException("Receipts are immutable");}
    @Override public int delete(Uri u,String s,String[] a){throw new UnsupportedOperationException("Receipts are immutable");}
}
