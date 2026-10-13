package au.monster.tracker;

import android.content.Context;
import android.net.Uri;
import android.graphics.*;
import android.media.ExifInterface;
import java.io.*;

public final class PhotoFiles {
    public static byte[] read(Context context,Uri uri)throws IOException {
        byte[] source;
        try(InputStream in=context.getContentResolver().openInputStream(uri);ByteArrayOutputStream out=new ByteArrayOutputStream()){
            if(in==null)throw new IOException("Could not open this photo.");byte[] b=new byte[8192];int n;
            while((n=in.read(b))!=-1){if(out.size()+n>20*1024*1024)throw new IOException("Choose a photo smaller than 20 MB.");out.write(b,0,n);}source=out.toByteArray();
        }
        BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(source,0,source.length,bounds);
        if(bounds.outWidth<=0||bounds.outHeight<=0)throw new IOException("This file is not a supported photo.");
        BitmapFactory.Options options=new BitmapFactory.Options();options.inSampleSize=1;
        while(Math.max(bounds.outWidth,bounds.outHeight)/options.inSampleSize>2000)options.inSampleSize*=2;
        Bitmap bitmap=BitmapFactory.decodeByteArray(source,0,source.length,options);if(bitmap==null)throw new IOException("Could not decode this photo.");
        try {
            Matrix matrix=new Matrix();
            try{ExifInterface exif=new ExifInterface(new ByteArrayInputStream(source));int orientation=exif.getAttributeInt(ExifInterface.TAG_ORIENTATION,ExifInterface.ORIENTATION_NORMAL);
                switch(orientation){case 2->matrix.setScale(-1,1);case 3->matrix.setRotate(180);case 4->matrix.setScale(1,-1);case 5->{matrix.setRotate(90);matrix.postScale(-1,1);}case 6->matrix.setRotate(90);case 7->{matrix.setRotate(270);matrix.postScale(-1,1);}case 8->matrix.setRotate(270);}
            }catch(IOException ignored){}
            if(!matrix.isIdentity()){Bitmap rotated=Bitmap.createBitmap(bitmap,0,0,bitmap.getWidth(),bitmap.getHeight(),matrix,true);if(rotated!=bitmap){bitmap.recycle();bitmap=rotated;}}
            int max=Math.max(bitmap.getWidth(),bitmap.getHeight());if(max>1600){float scale=1600f/max;Bitmap scaled=Bitmap.createScaledBitmap(bitmap,Math.max(1,Math.round(bitmap.getWidth()*scale)),Math.max(1,Math.round(bitmap.getHeight()*scale)),true);if(scaled!=bitmap){bitmap.recycle();bitmap=scaled;}}
            for(int quality=90;quality>=40;quality-=10){ByteArrayOutputStream out=new ByteArrayOutputStream();bitmap.compress(Bitmap.CompressFormat.JPEG,quality,out);if(out.size()<=Receipts.MAX_PHOTO_BYTES)return out.toByteArray();}
            throw new IOException("Photo is too large after compression. Choose a smaller photo.");
        }finally{bitmap.recycle();}
    }
    public static void validateStored(byte[] bytes){BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(bytes,0,bytes.length,bounds);if(bounds.outWidth<=0||bounds.outHeight<=0||bounds.outWidth>1600||bounds.outHeight>1600)throw new IllegalArgumentException("Invalid receipt image or image dimensions. Nothing was imported.");}
    private PhotoFiles(){}
}
