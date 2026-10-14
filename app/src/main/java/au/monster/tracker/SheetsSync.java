package au.monster.tracker;

import android.app.job.*;
import android.content.*;
import java.net.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Retries append-only uploads; local transactions remain the source of truth. */
public final class SheetsSync {
    private static final int NOW=8201,PERIODIC=8202;
    private static final Object LOCK=new Object();
    private final Context context;
    private final SharedPreferences prefs;
    private final PaymentSettings pairing;
    public SheetsSync(Context c){context=c.getApplicationContext();prefs=context.getSharedPreferences("sheets-state",Context.MODE_PRIVATE);pairing=new PaymentSettings(context,"sheets-pairing");}
    public String url(){return pairing.url();}
    public boolean configured(){return pairing.configured();}
    public boolean automatic(){return prefs.getBoolean("automatic",false);}
    public String token()throws Exception{return pairing.token();}
    public String status(int total){long last=prefs.getLong("last",0);return (configured()?Math.max(0,total-prefs.getInt("uploaded",0))+" records pending":"Not connected")+"\nLast successful upload: "+(last==0?"Never":Ledger.displayTime(last))+(prefs.getString("error","").isEmpty()?"":"\n"+prefs.getString("error",""));}
    public void save(String url,String token,boolean auto)throws Exception{
        URI u=new URI(url.trim());
        if(!"https".equals(u.getScheme())||!"script.google.com".equals(u.getHost())||u.getPort()!=-1||u.getUserInfo()!=null||!u.getPath().matches("/macros/s/[A-Za-z0-9_-]+/exec")||u.getQuery()!=null||u.getFragment()!=null)throw new IllegalArgumentException("Use the deployed Google Apps Script /exec URL.");
        boolean changed=!url.trim().equals(pairing.url());pairing.save(url,token,false);
        var e=prefs.edit().putBoolean("automatic",auto).remove("error");if(changed)e.putInt("uploaded",0).remove("last");if(!e.commit())throw new IOException("Could not save sync settings.");schedule(context,true);
    }
    public static void schedule(Context c,boolean manual){
        SheetsSync s=new SheetsSync(c);JobScheduler jobs=c.getSystemService(JobScheduler.class);if(!s.configured())return;
        ComponentName service=new ComponentName(c,SheetsSyncService.class);
        if(s.automatic()){if(jobs.getPendingJob(PERIODIC)==null)jobs.schedule(new JobInfo.Builder(PERIODIC,service).setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPeriodic(15*60*1000L).setPersisted(true).build());}else jobs.cancel(PERIODIC);
        if(manual||s.automatic())if(jobs.getPendingJob(NOW)==null)jobs.schedule(new JobInfo.Builder(NOW,service).setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setBackoffCriteria(30000,JobInfo.BACKOFF_POLICY_EXPONENTIAL).setPersisted(true).build());
    }
    public static void requestAutomatic(Context c){try{schedule(c,false);}catch(RuntimeException ignored){/* A scheduling failure must never turn a saved transaction into a reported save failure. */}}
    public void upload()throws Exception{
        synchronized(LOCK){
            if(!configured())return;List<Ledger.Event> events;try(Store store=new Store(context)){events=store.snapshot().events();}
            String destination=url(),secret=token();
            try{
                for(int start=0;start<events.size();start+=100){
                    if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("Upload interrupted.");
                    List<Object> batch=new ArrayList<>();for(var event:events.subList(start,Math.min(start+100,events.size())))batch.add(Backup.eventMap(event));
                    Map<String,Object> request=new LinkedHashMap<>();request.put("token",secret);request.put("events",batch);
                    Map<?,?> reply=post(destination,Json.write(request));
                    if(!Boolean.TRUE.equals(reply.get("ok"))||!(reply.get("accepted") instanceof Long n)||n!=batch.size())throw new IOException("Sheets rejected the upload. Check setup and transaction conflicts.");
                }
                if(!destination.equals(url())||!secret.equals(token()))return;
                if(!prefs.edit().putInt("uploaded",events.size()).putLong("last",System.currentTimeMillis()).remove("error").commit())throw new IOException("Could not save acknowledgment.");
            }catch(Exception e){prefs.edit().putString("error","Upload incomplete; records remain on your phone. Check internet and Sheets setup, then retry.").commit();throw e;}
        }
    }
    private static Map<?,?> post(String address,String body)throws Exception{
        HttpURLConnection c=(HttpURLConnection)new URL(address).openConnection();c.setConnectTimeout(15000);c.setReadTimeout(25000);c.setInstanceFollowRedirects(false);c.setRequestMethod("POST");c.setDoOutput(true);c.setRequestProperty("Content-Type","application/json; charset=UTF-8");
        try{
            try(OutputStream out=c.getOutputStream()){out.write(body.getBytes(StandardCharsets.UTF_8));}int code=c.getResponseCode();
            if(code==302||code==303){URI redirect=new URI(c.getHeaderField("Location"));if(!"https".equals(redirect.getScheme())||!"script.googleusercontent.com".equals(redirect.getHost())||redirect.getUserInfo()!=null||redirect.getPort()!=-1)throw new IOException("Unexpected Sheets redirect.");c.disconnect();c=(HttpURLConnection)redirect.toURL().openConnection();c.setConnectTimeout(15000);c.setReadTimeout(25000);c.setInstanceFollowRedirects(false);code=c.getResponseCode();}
            if(code!=200)throw new IOException("Sheets endpoint unavailable.");
            try(InputStream in=c.getInputStream();ByteArrayOutputStream out=new ByteArrayOutputStream()){byte[] b=new byte[4096];int n;while((n=in.read(b))!=-1){out.write(b,0,n);if(out.size()>16384)throw new IOException("Unexpected Sheets response.");}Object parsed=Json.parse(new String(out.toByteArray(),StandardCharsets.UTF_8));if(!(parsed instanceof Map<?,?> m))throw new IOException("Invalid Sheets response.");return m;}
        }finally{c.disconnect();}
    }
}
