package au.monster.tracker;

import android.app.*;
import android.os.*;
import android.content.pm.PackageManager;
import android.widget.*;
import java.util.*;
import java.util.concurrent.*;
import com.stripe.stripeterminal.Terminal;
import com.stripe.stripeterminal.log.LogLevel;
import com.stripe.stripeterminal.external.models.LocaleConfig;
import com.stripe.stripeterminal.external.callable.*;
import com.stripe.stripeterminal.external.models.*;

/** A checkout is durable before networking. Every retry retrieves the same server PaymentIntent. */
public final class StripeActivity extends Activity {
    private static final ExecutorService TOKEN_NETWORK=Executors.newSingleThreadExecutor();
    private final ExecutorService network=Executors.newSingleThreadExecutor();
    private Store store;private Ledger.Event sale;private PaymentSettings settings;private PaymentClient api;
    private TextView status;private Button retry,cancel,close;private boolean working=false,finished=false;private Cancelable operation;
    @Override public void onCreate(Bundle saved){super.onCreate(saved);store=new Store(this);sale=store.checkout();settings=new PaymentSettings(this);api=new PaymentClient(settings);
        LinearLayout layout=new LinearLayout(this);layout.setOrientation(LinearLayout.VERTICAL);int insetPadding=Math.round(16*getResources().getDisplayMetrics().density);layout.setPadding(insetPadding,insetPadding,insetPadding,insetPadding);layout.setOnApplyWindowInsetsListener((view,insets)->{layout.setPadding(insetPadding,insetPadding+insets.getSystemWindowInsetTop(),insetPadding,insetPadding+insets.getSystemWindowInsetBottom());return insets;});layout.setBackgroundColor(0xff101410);
        TextView title=new TextView(this);title.setText(settings.live()?"Stripe Tap to Pay":"Stripe test payment");title.setTextSize(26);title.setTextColor(0xffb6f552);layout.addView(title);
        status=new TextView(this);status.setTextColor(0xfff0f5eb);status.setTextSize(18);status.setPadding(0,30,0,30);status.setAccessibilityLiveRegion(android.view.View.ACCESSIBILITY_LIVE_REGION_POLITE);layout.addView(status);
        retry=new Button(this);retry.setText("Check status / retry same payment");retry.setOnClickListener(v->checkAndPay());layout.addView(retry);
        cancel=new Button(this);cancel.setText("Cancel unpaid payment");cancel.setOnClickListener(v->cancelPayment());layout.addView(cancel);
        close=new Button(this);close.setText("Return to tracker");close.setOnClickListener(v->{if(!working)finish();});layout.addView(close);setContentView(layout);layout.requestApplyInsets();
        if(sale==null){finished=true;show("No payment is pending.");return;}
        show((settings.live()?"Amount: ":"TEST ONLY · no real charge: ")+Ledger.money(sale.revenue())+"\nA pending payment blocks new ledger entries until resolved.");
        checkAndPay();
    }
    private void show(String text){status.setText(text);retry.setEnabled(!working&&!finished);cancel.setEnabled(!finished);close.setEnabled(!working);}
    private void fail(Exception e){working=false;operation=null;show((e.getMessage()==null?"Payment could not complete.":e.getMessage())+"\nUse Check status / retry. The same payment ID is retained.");}
    private void checkAndPay(){if(working||finished)return;if(!settings.configured()){show("Connect your secure Stripe backend in Settings first.");return;}working=true;show("Checking this payment with Stripe…");network.execute(()->{try{var config=api.post("/config",new LinkedHashMap<>());if(!Objects.equals(config.get("live"),settings.live()))throw new IllegalStateException("Backend payment mode differs from the phone. Resolve this with the original backend.");var response=api.sale("/payment",sale);runOnUiThread(()->handle(response,(String)config.get("location")));}catch(Exception e){runOnUiThread(()->fail(e));}});}
    private void handle(Map<String,Object> response,String location){
        try{String state=(String)response.get("status");if(!Objects.equals(response.get("live"),settings.live())||!Objects.equals(response.get("amount"),sale.revenue()))throw new IllegalStateException("Payment does not match this sale.");
            if("succeeded".equals(state)){
                network.execute(()->{try{
                    if(settings.live()){
                        if(!(response.get("fee") instanceof Long fee))throw new IllegalStateException("Payment received. Stripe's actual fee is still pending. Do not charge again; check status later.");
                        String note="Stripe "+response.get("id")+" · "+sale.note();if(note.length()>500)note=note.substring(0,500);
                        var paid=new Ledger.Event(sale.id(),sale.timestamp(),sale.recordedAt(),sale.type(),sale.quantity(),"card",sale.revenue(),fee,0,note,null);store.finishCheckout(paid);SheetsSync.schedule(this,false);
                    }else store.clearCheckout(sale.id());
                    runOnUiThread(()->{working=false;finished=true;operation=null;show(settings.live()?"Payment received and sale saved once, including Stripe's actual fee.":"Test payment succeeded. No real sale or stock change was recorded.");});
                }catch(Exception e){runOnUiThread(()->fail(e));}});return;
            }
            if("canceled".equals(state)){network.execute(()->{store.clearCheckout(sale.id());runOnUiThread(()->{working=false;finished=true;show("Payment canceled. No sale recorded.");});});return;}
            if("processing".equals(state)||"requires_capture".equals(state)){working=false;show("Payment is processing. Check status later. Do not collect another payment.");return;}
            if(!"requires_payment_method".equals(state)&&!"requires_confirmation".equals(state))throw new IllegalStateException("Unsupported payment state. Check Stripe before collecting again.");
            if(android.os.Build.VERSION.SDK_INT<33)throw new IllegalStateException("Tap to Pay requires Android 13 or newer.");
            if(checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION)!=PackageManager.PERMISSION_GRANTED){working=false;show("Stripe requires precise location access. Grant it to continue.");requestPermissions(new String[]{android.Manifest.permission.ACCESS_FINE_LOCATION,android.Manifest.permission.ACCESS_COARSE_LOCATION},71);return;}
            connectAndProcess((String)response.get("clientSecret"),location);
        }catch(Exception e){fail(e);}
    }
    @Override public void onRequestPermissionsResult(int request,String[] permissions,int[] grants){super.onRequestPermissionsResult(request,permissions,grants);if(request==71){if(checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION)==PackageManager.PERMISSION_GRANTED)checkAndPay();else show("Precise location was not granted. You can cancel this unpaid payment or grant access in Android Settings.");}}
    private void initialize()throws Exception{
        if(Terminal.isInitialized())return;
        PaymentClient tokenApi=new PaymentClient(new PaymentSettings(getApplicationContext()));
        ConnectionTokenProvider provider=callback->TOKEN_NETWORK.execute(()->{try{var response=tokenApi.post("/connection_token",new LinkedHashMap<>());callback.onSuccess((String)response.get("secret"));}catch(Exception e){callback.onFailure(new ConnectionTokenException("Could not connect to the payment backend.",e));}});
        Terminal.init(getApplicationContext(),LogLevel.ERROR,provider,new TerminalListener(){},null,LocaleConfig.CardLanguagePreferenceIfAvailable.INSTANCE);
    }
    private void connectAndProcess(String secret,String location)throws Exception{
        initialize();if(Terminal.getInstance().getConnectedReader()!=null){operation=null;Terminal.getInstance().disconnectReader(new Callback(){public void onSuccess(){runOnUiThread(()->{try{Terminal.getInstance().clearCachedCredentials();connectAndProcess(secret,location);}catch(Exception e){fail(e);}});}public void onFailure(TerminalException e){runOnUiThread(()->fail(e));}});return;}Terminal.getInstance().clearCachedCredentials();
        show("Connecting to "+(settings.live()?"Tap to Pay":"Stripe's simulated reader")+"…");
        var config=new EasyConnectConfiguration.TapToPayEasyConnectConfiguration(new DiscoveryConfiguration.TapToPayDiscoveryConfiguration(!settings.live()),new ConnectionConfiguration.TapToPayConnectionConfiguration(new TapUseCase.Pay(location),true,new TapToPayReaderListener(){}));
        operation=Terminal.getInstance().easyConnect(config,new ReaderCallback(){public void onSuccess(Reader reader){runOnUiThread(()->process(secret));}public void onFailure(TerminalException e){runOnUiThread(()->fail(e));}});
    }
    private void process(String secret){operation=null;show(settings.live()?"Ready for customer to tap. Follow Stripe's payment screen.":"Processing a simulated test payment…");Terminal.getInstance().retrievePaymentIntent(secret,new PaymentIntentCallback(){public void onSuccess(PaymentIntent intent){runOnUiThread(()->{try{operation=Terminal.getInstance().processPaymentIntent(intent,new CollectPaymentIntentConfiguration.Builder().build(),new ConfirmPaymentIntentConfiguration.Builder().build(),new PaymentIntentCallback(){public void onSuccess(PaymentIntent paid){runOnUiThread(()->refreshAfterProcess());}public void onFailure(TerminalException e){runOnUiThread(()->fail(e));}});}catch(Exception e){fail(e);}});}public void onFailure(TerminalException e){runOnUiThread(()->fail(e));}});}
    private void refreshAfterProcess(){operation=null;show("Verifying payment and actual fee with Stripe…");network.execute(()->{try{var response=api.sale("/status",sale);runOnUiThread(()->handle(response,null));}catch(Exception e){runOnUiThread(()->fail(e));}});}
    private void cancelPayment(){if(finished)return;
        // Cancellation is unavailable during unknown network processing; wait for that result first.
        if(working&&operation==null){show("Wait for the current Stripe response, then check status or cancel.");return;}
        if(operation!=null){Cancelable current=operation;current.cancel(new Callback(){public void onSuccess(){runOnUiThread(()->{operation=null;working=false;cancelPayment();});}public void onFailure(TerminalException e){runOnUiThread(()->fail(e));}});return;}
        working=true;show("Checking with Stripe before canceling…");network.execute(()->{try{var response=api.sale("/cancel",sale);runOnUiThread(()->handle(response,null));}catch(Exception e){runOnUiThread(()->fail(e));}});
    }
    @Override public void onBackPressed(){if(!working)super.onBackPressed();else show("Finish or cancel the current payment before leaving.");}
    @Override protected void onDestroy(){network.execute(store::close);network.shutdown();super.onDestroy();}
}
