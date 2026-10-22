package au.monster.tracker;
import android.app.job.*;
import java.util.concurrent.*;

public final class SheetsSyncService extends JobService {
    private final ExecutorService executor=Executors.newSingleThreadExecutor();
    private final ConcurrentHashMap<Integer,Future<?>> running=new ConcurrentHashMap<>();
    @Override public boolean onStartJob(JobParameters p){
        FutureTask<Void> task=new FutureTask<>(()->{boolean retry=false;try{new SheetsSync(this).upload();}catch(Exception e){retry=true;}final boolean again=retry;new android.os.Handler(getMainLooper()).post(()->{if(running.remove(p.getJobId())!=null)jobFinished(p,again);});return null;});running.put(p.getJobId(),task);executor.execute(task);return true;
    }
    @Override public boolean onStopJob(JobParameters p){Future<?> task=running.remove(p.getJobId());if(task!=null)task.cancel(true);return true;}
    @Override public void onDestroy(){for(Future<?> task:running.values())task.cancel(true);running.clear();executor.shutdownNow();super.onDestroy();}
}
