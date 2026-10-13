package au.monster.tracker;

import android.content.Context;
import android.graphics.*;
import android.graphics.pdf.PdfRenderer;
import android.media.ExifInterface;
import android.os.ParcelFileDescriptor;
import com.google.android.gms.tasks.Tasks;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.*;
import com.google.mlkit.vision.text.latin.TextRecognizerOptions;
import java.io.*;
import java.util.concurrent.TimeUnit;

/** Bundled Latin OCR. Call from a background worker. Originals are never altered. */
public final class ReceiptOcr {
    public static String scan(Context context,Purchases.Receipt receipt)throws Exception{
        TextRecognizer recognizer=TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS);try{
            byte[] bytes=receipt.content();if(!receipt.mime().equals("application/pdf")){
                BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(bytes,0,bytes.length,bounds);if(bounds.outWidth<=0||bounds.outHeight<=0)throw new IOException("This receipt image cannot be decoded. Keep the original and enter its values manually.");
                BitmapFactory.Options options=new BitmapFactory.Options();options.inSampleSize=1;while((long)(bounds.outWidth/options.inSampleSize)*(bounds.outHeight/options.inSampleSize)>2500000L||Math.max(bounds.outWidth,bounds.outHeight)/options.inSampleSize>2400)options.inSampleSize*=2;
                Bitmap bitmap=BitmapFactory.decodeByteArray(bytes,0,bytes.length,options);if(bitmap==null)throw new IOException("Image decoding failed.");int rotation=0;try(InputStream in=new ByteArrayInputStream(bytes)){ExifInterface exif=new ExifInterface(in);int orientation=exif.getAttributeInt(ExifInterface.TAG_ORIENTATION,ExifInterface.ORIENTATION_NORMAL);if(orientation==ExifInterface.ORIENTATION_ROTATE_90)rotation=90;else if(orientation==ExifInterface.ORIENTATION_ROTATE_180)rotation=180;else if(orientation==ExifInterface.ORIENTATION_ROTATE_270)rotation=270;}catch(IOException ignored){}
                try{return Tasks.await(recognizer.process(InputImage.fromBitmap(bitmap,rotation)),45,TimeUnit.SECONDS).getText();}finally{bitmap.recycle();}
            }
            File temporary=File.createTempFile("receipt-ocr-",".pdf",context.getCacheDir());try{
                try(OutputStream out=new FileOutputStream(temporary)){out.write(bytes);}StringBuilder text=new StringBuilder();
                try(ParcelFileDescriptor descriptor=ParcelFileDescriptor.open(temporary,ParcelFileDescriptor.MODE_READ_ONLY);PdfRenderer renderer=new PdfRenderer(descriptor)){
                    int count=Math.min(renderer.getPageCount(),20);for(int i=0;i<count;i++)try(PdfRenderer.Page page=renderer.openPage(i)){
                        float scale=Math.min(2400f/Math.max(page.getWidth(),page.getHeight()),(float)Math.sqrt(2500000.0/((double)page.getWidth()*page.getHeight())));
                        int width=Math.max(1,Math.round(page.getWidth()*scale)),height=Math.max(1,Math.round(page.getHeight()*scale));Bitmap bitmap=Bitmap.createBitmap(width,height,Bitmap.Config.ARGB_8888);try{bitmap.eraseColor(Color.WHITE);page.render(bitmap,null,null,PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY);text.append(Tasks.await(recognizer.process(InputImage.fromBitmap(bitmap,0)),45,TimeUnit.SECONDS).getText()).append('\n');}finally{bitmap.recycle();}
                    }if(renderer.getPageCount()>20)text.append("\n[Only the first 20 pages were scanned; the entire original PDF is retained.]\n");
                }return text.toString();
            }finally{temporary.delete();}
        }finally{recognizer.close();}
    }
    private ReceiptOcr(){}
}
