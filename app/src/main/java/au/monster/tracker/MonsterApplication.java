package au.monster.tracker;
import android.app.Application;
import com.stripe.stripeterminal.TerminalApplicationDelegate;
import com.stripe.stripeterminal.taptopay.TapToPay;
public final class MonsterApplication extends Application {
    @Override public void onCreate(){super.onCreate();if(TapToPay.Companion.isInTapToPayProcess())return;TerminalApplicationDelegate.onCreate(this);try{BackupJob.schedule(this);try(Store store=new Store(this)){var queued=store.recoverPending();if(queued!=null)store.acknowledge(queued.id());if(store.checkout()!=null)PaymentCheckJob.schedule(this);}}catch(RuntimeException e){new BackupSettings(this).status("Automatic backup scheduling failed. Existing records are safe; use manual backup: "+e.getMessage());}}
}
