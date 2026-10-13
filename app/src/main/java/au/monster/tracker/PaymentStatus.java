package au.monster.tracker;
import java.util.*;

/** Shared verified finalization for SDK callbacks and background recovery; never initiates a charge. */
public final class PaymentStatus {
    public static boolean apply(Store store,Ledger.Event sale,Map<String,Object> response,boolean live){if(!Objects.equals(response.get("live"),live)||!Objects.equals(response.get("amount"),sale.revenue())||!Objects.equals(response.get("currency"),"aud"))throw new IllegalArgumentException("Verified payment mode/amount/currency does not match the saved sale.");String status=Purchases.str(response,"status");if(status.equals("canceled")){store.clearCheckout(sale.id());return true;}if(!status.equals("succeeded"))return false;if(!live){store.clearCheckout(sale.id());return true;}if(response.get("fee")==null)return false;if(!(response.get("fee") instanceof Long))throw new IllegalArgumentException("Invalid verified payment fee.");long fee=Purchases.num(response,"fee");String id=Purchases.str(response,"id");if(!id.matches("pi_[A-Za-z0-9]+"))throw new IllegalArgumentException("Invalid Stripe payment ID.");String note="Stripe "+id+" · "+sale.note();if(note.length()>500)note=note.substring(0,500);var paid=new Ledger.Event(sale.id(),sale.timestamp(),sale.recordedAt(),sale.type(),sale.quantity(),"card",sale.revenue(),fee,0,note,null);store.finishCheckout(paid);return true;}
    private PaymentStatus(){}
}
