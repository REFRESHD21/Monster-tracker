package au.monster.tracker;
import android.app.job.*;
import android.content.*;
import java.util.*;
import java.util.concurrent.*;

/** Android schedules are approximate under battery restrictions. Local save does not require a network. */
public final class BackupJob extends JobService {
    private static final int ID=786431;private volatile int generation;
    public static void schedule(Context context){BackupSettings settings=new BackupSettings(context);JobScheduler scheduler=context.getSystemService(JobScheduler.class);if(!settings.enabled()){scheduler.cancel(ID);return;}long period=settings.hours()*3600000L;JobInfo existing=scheduler.getPendingJob(ID);if(existing!=null&&existing.getIntervalMillis()==period)return;JobInfo job=new JobInfo.Builder(ID,new ComponentName(context,BackupJob.class)).setPeriodic(period,3600000L).setPersisted(true).setBackoffCriteria(30*60000L,JobInfo.BACKOFF_POLICY_EXPONENTIAL).build();if(scheduler.schedule(job)==JobScheduler.RESULT_FAILURE)throw new IllegalStateException("Android could not schedule backups. Use Back up now and check battery restrictions.");}
    @Override public boolean onStartJob(JobParameters parameters){BackupSettings settings=new BackupSettings(this);if(!settings.enabled())return false;int ticket=++generation;new Thread(()->{boolean retry=false;char[] password=null;try{password=settings.password();var file=BackupFiles.create(this,password);if(ticket!=generation)return;BackupFiles.retain(this,7);String message="Verified local backup: "+Ledger.displayTime(System.currentTimeMillis());try{BackupFiles.copy(this,file,settings.folder());if(!settings.folder().isEmpty())message+=" · provider folder copy verified";}catch(Exception e){message+=" · provider copy failed; local recovery copy is safe: "+e.getMessage();}settings.status(message);}catch(Throwable e){retry=true;settings.status("Automatic backup failed; existing records/copies remain intact: "+e.getMessage());}finally{if(password!=null)Arrays.fill(password,'\0');if(ticket==generation)jobFinished(parameters,retry);}},"monster-backup").start();return true;}
    @Override public boolean onStopJob(JobParameters parameters){generation++;return true;}
}
