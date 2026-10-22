package au.monster.tracker;
import android.app.job.*;
import android.content.*;
import java.util.*;

/** Online status recovery for an already saved checkout. It never creates/processes a payment. */
public final class PaymentCheckJob extends JobService {
    private static final int ID=786432;private volatile int generation;
    public static void schedule(Context context){if(!new PaymentSettings(context).configured())return;JobScheduler scheduler=context.getSystemService(JobScheduler.class);if(scheduler.getPendingJob(ID)!=null)return;JobInfo job=new JobInfo.Builder(ID,new ComponentName(context,PaymentCheckJob.class)).setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPersisted(true).setMinimumLatency(30000).setBackoffCriteria(30000,JobInfo.BACKOFF_POLICY_EXPONENTIAL).build();scheduler.schedule(job);}
    @Override public boolean onStartJob(JobParameters parameters){int ticket=++generation;new Thread(()->{boolean retry=false;try(Store store=new Store(this)){var sale=store.checkout();if(sale!=null){PaymentSettings settings=new PaymentSettings(this);PaymentClient api=new PaymentClient(settings);var config=api.post("/config",new LinkedHashMap<>());if(!Objects.equals(config.get("live"),settings.live()))throw new IllegalStateException("Payment mode mismatch.");retry=!PaymentStatus.apply(store,sale,api.sale("/status",sale),settings.live());}}catch(Exception e){retry=true;}finally{if(ticket==generation)jobFinished(parameters,retry);}},"monster-payment-status").start();return true;}
    @Override public boolean onStopJob(JobParameters parameters){generation++;return true;}
}
