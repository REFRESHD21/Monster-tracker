package au.monster.tracker;
import java.util.*;
public final class CatalogTests {
    private static int passed;
    private static void eq(Object a,Object b){if(!Objects.equals(a,b))throw new AssertionError(a+" != "+b);}
    private static void check(String name,Runnable test){test.run();passed++;System.out.println("PASS "+name);}
    private static void reject(Runnable test){try{test.run();throw new AssertionError("Accepted invalid input");}catch(IllegalArgumentException expected){}}
    public static void main(String[] args){long now=System.currentTimeMillis();String id=Ledger.id();var p=new Catalog.Product(id,"Ultra",5,24,12,2500,"Supplier");
        check("opening history remains unassigned and unknown",()->{var opening=Ledger.opening(now);eq(Catalog.stock(opening,new HashMap<>(),Ledger.list()).get(Catalog.LEGACY),20L);eq(opening.get(1).timestamp(),null);});
        check("flavour transfers preserve overall stock",()->{var stock=Catalog.stock(Ledger.opening(now),new HashMap<>(),Ledger.list(new Catalog.Transfer(Ledger.id(),Catalog.LEGACY,id,8,now,"Counted")));eq(stock.get(id),8L);eq(stock.get(Catalog.LEGACY),12L);});
        check("deal allocation and traceable undo",()->{List<Ledger.Event> events=new ArrayList<>(Ledger.opening(now));var e=Ledger.event("deal",2,"cash",600,0,0,"",now,null);events.add(e);Map<String,List<Catalog.Allocation>> allocations=new HashMap<>();allocations.put(e.id(),Ledger.list(new Catalog.Allocation(id,2)));var transfers=Ledger.list(new Catalog.Transfer(Ledger.id(),Catalog.LEGACY,id,8,now,"Counted"));eq(Catalog.stock(events,allocations,transfers).get(id),6L);events.add(Ledger.event("undo",0,"none",0,0,0,"Mistake",now,e.id()));eq(Catalog.stock(events,allocations,transfers).get(id),8L);});
        check("shopping subtracts pending deliveries and rounds packs",()->{var list=Catalog.shopping(p,2,5);eq(list.required(),17L);eq(list.packs(),2L);eq(list.estimatedCost(),5000L);eq(Catalog.shopping(p,5,0).required(),0L);});
        check("zero-stock and fully ordered stock",()->{eq(Catalog.shopping(p,0,24).required(),0L);eq(Catalog.shopping(p,0,0).low(),true);});
        check("barcode leading zeros retained",()->{eq(Catalog.barcode(" 0012345678905 "),"0012345678905");reject(()->Catalog.barcode("bad/code"));});
        check("invalid stock preferences rejected",()->reject(()->new Catalog.Product(id,"Ultra",25,24,12,2500,"")));
        check("allocation quantity mismatch rejected",()->{var e=Ledger.event("deal",2,"cash",600,0,0,"",now,null);reject(()->Catalog.forEvent(e,Map.of(e.id(),Ledger.list(new Catalog.Allocation(id,1)))));});
        check("OCR supplier totals GST date and multipacks remain suggestions",()->{var r=ReceiptParser.parse("WOOLWORTHS\nInvoice No: A123\n13/10/2026\nMonster qty 2 24 pack $50.00 $100.00\nTOTAL $100.00\nGST $9.09");eq(r.supplier(),"WOOLWORTHS");eq(r.reference(),"A123");eq(r.total(),10000L);eq(r.gst(),909L);eq(r.items().size(),1);eq(r.items().get(0).packs(),2L);eq(r.items().get(0).packSize(),24L);eq(r.items().get(0).unitPrice(),5000L);eq(Ledger.displayTime(r.date()).contains("2026"),true);});
        check("OCR unknown dates remain unknown",()->{eq(ReceiptParser.parse("SUPPLIER\nMonster $50.00\nTOTAL $50.00").date(),null);eq(ReceiptParser.parse("SUPPLIER\n31/02/2026").date(),null);});
        check("zero-target flavours do not generate shopping alerts",()->eq(Catalog.shopping(new Catalog.Product(Ledger.id(),"Inactive reorder",0,0,24,5000,""),0,0).low(),false));
        System.out.println("CATALOG RESULTS: "+passed+" passed, 0 failed.");
    }
}
