package au.monster.tracker;

import java.time.Instant;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;

/** Runs the production Java ledger/backup code on a host JVM, without Android or internet. */
public final class CoreTests {
    static int passed=0,failed=0;static final long NOW=Instant.parse("2026-10-12T00:00:00Z").toEpochMilli();
    interface Check {void run()throws Exception;}
    static void test(String name,Check check){try{check.run();passed++;System.out.println("PASS "+name);}catch(Throwable e){failed++;System.err.println("FAIL "+name+": "+e);e.printStackTrace();}}
    static void equal(Object got,Object want){if(!Objects.equals(got,want))throw new AssertionError("got="+got+", expected="+want);}
    static void reject(Runnable r){try{r.run();}catch(IllegalArgumentException ex){return;}throw new AssertionError("Expected validation failure.");}
    static List<Ledger.Event> opening(){return new ArrayList<>(Ledger.opening(NOW));}
    static Ledger.Event sale(String id,String type,String payment,long revenue,long fee){return new Ledger.Event(id,NOW,NOW,type,type.equals("single")?1:2,payment,revenue,fee,0,"",null);}
    static Ledger.Event stock(String id,String type,long quantity,long cost){return new Ledger.Event(id,NOW,NOW,type,quantity,"none",0,0,cost,"stock note",null);}
    static Ledger.Event undo(String id,String target){return new Ledger.Event(id,NOW,NOW,"undo",0,"none",0,0,0,"Correct mistaken entry",target);}
    static List<Ledger.Event> add(List<Ledger.Event> es,Ledger.Event e){Ledger.validate(e,es);List<Ledger.Event> n=new ArrayList<>(es);n.add(e);return n;}
    static Backup.Data data(List<Ledger.Event> es){return new Backup.Data(es,new Ledger.Prices(350,600));}
    @SuppressWarnings("unchecked") static Map<String,Object> signedRoot(String text){return (Map<String,Object>)Json.parse(text);}
    static String resign(Map<String,Object> root)throws Exception {root.remove("sha256");byte[] h=MessageDigest.getInstance("SHA-256").digest(Json.write(root).getBytes(StandardCharsets.UTF_8));StringBuilder b=new StringBuilder();for(byte x:h)b.append(String.format("%02x",x&255));root.put("sha256",b.toString());return Json.write(root);}
    public static void main(String[] args)throws Exception {
        passed=0;failed=0;Files.createDirectories(Path.of(".build"));
        test("opening inventory and money",()->{var t=Ledger.totals(opening());equal(t.stock(),20L);equal(t.missing(),4L);equal(t.revenue(),0L);equal(t.purchases(),5000L);equal(t.result(),-5000L);});
        test("opening dates remain unknown",()->{for(var e:opening())equal(e.timestamp(),null);equal(Ledger.displayTime(null),"Date unknown");Ledger.validateAll(opening());});
        test("single cash stock deduction",()->{var t=Ledger.totals(add(opening(),sale("sale-single-0001","single","cash",350,0)));equal(t.stock(),19L);equal(t.singles(),1L);equal(t.sold(),1L);equal(t.cash(),350L);equal(t.result(),-4650L);});
        test("two-can deal and card fee",()->{var t=Ledger.totals(add(opening(),sale("sale-deal-00001","deal","card",600,25)));equal(t.stock(),18L);equal(t.deals(),1L);equal(t.sold(),2L);equal(t.card(),600L);equal(t.fees(),25L);equal(t.result(),-4425L);});
        test("purchase plus revenue calculation",()->{var es=add(add(opening(),stock("restock-test-001","restock",24,5000)),sale("single-test-001","single","cash",350,0));var t=Ledger.totals(es);equal(t.stock(),43L);equal(t.purchases(),10000L);equal(t.revenue(),350L);equal(t.result(),-9650L);});
        test("missing damaged and lost are not sales",()->{var es=opening();for(String kind:Ledger.list("missing","damaged","lost"))es=add(es,stock("adjustment-"+kind,kind,1,0));var t=Ledger.totals(es);equal(t.stock(),17L);equal(t.missing(),7L);equal(t.revenue(),0L);});
        test("prevent overselling and malformed deal",()->{var es=add(opening(),stock("missing-all-0001","missing",19,0));reject(()->Ledger.validate(sale("deal-no-stock01","deal","cash",600,0),es));reject(()->Ledger.validate(new Ledger.Event("malformed-deal1",NOW,NOW,"deal",1,"cash",600,0,0,"",null),opening()));});
        test("cash fees and excessive card fees rejected",()->{reject(()->Ledger.validate(sale("bad-cash-fee01","single","cash",350,10),opening()));reject(()->Ledger.validate(sale("bad-card-fee01","single","card",350,351),opening()));});
        test("undo retains original and reverses all effects",()->{var sale=sale("card-sale-undo1","single","card",350,20);var es=add(add(opening(),sale),undo("undo-sale-test1",sale.id()));var t=Ledger.totals(es);equal(es.size(),4);equal(es.get(2),sale);equal(t.stock(),20L);equal(t.card(),0L);equal(t.fees(),0L);equal(t.result(),-5000L);});
        test("undo opening missing restores four",()->{var es=add(opening(),undo("undo-opening-01",Ledger.OPEN_MISSING));equal(Ledger.totals(es).stock(),24L);equal(Ledger.totals(es).missing(),0L);equal(es.get(1).timestamp(),null);});
        test("duplicate undo and undo-of-undo rejected",()->{var es=add(opening(),undo("undo-first-0001",Ledger.OPEN_MISSING));reject(()->Ledger.validate(undo("undo-second-001",Ledger.OPEN_MISSING),es));reject(()->Ledger.validate(undo("undo-undo-00001","undo-first-0001"),es));});
        test("undo consumed restock cannot make stock negative",()->{var es=add(add(opening(),stock("stock-to-undo01","restock",2,500)),stock("missing-22-0001","missing",22,0));reject(()->Ledger.validate(undo("undo-stock-0001","stock-to-undo01"),es));});
        test("unique transaction IDs",()->{var e=sale("duplicate-id001","single","cash",350,0);var es=add(opening(),e);reject(()->Ledger.validate(e,es));});
        test("prices change without modifying old sale",()->{var e=sale("old-price-00001","single","cash",350,0);var newPrices=new Ledger.Prices(425,750);equal(newPrices.single(),425L);equal(e.revenue(),350L);equal(Ledger.totals(add(opening(),e)).revenue(),350L);});
        test("exact cents and Perth timezone",()->{equal(Ledger.cents("3.50"),350L);equal(Ledger.cents("0.01"),1L);reject(()->Ledger.cents("3.501"));reject(()->Ledger.cents("-1"));if(!Ledger.displayTime(NOW).contains("08:00:00"))throw new AssertionError("Not Perth time");});
        test("JSON backup roundtrip includes notes prices and unknown dates",()->{var e=new Ledger.Event("quoted-note-001",NOW,NOW,"single",1,"cash",350,0,0,"a \"note\"\nnext line 🥤",null);var before=new Backup.Data(add(opening(),e),new Ledger.Prices(425,725));var after=Backup.decode(Backup.encode(before));equal(after.events(),before.events());equal(after.prices(),before.prices());equal(after.events().get(0).timestamp(),null);});
        test("restore to replacement phone skips opening seeds",()->{var current=Ledger.opening(NOW+1000);var original=add(opening(),sale("restore-sale001","single","cash",350,0));var merged=Ledger.merge(current,original);equal(merged.size(),3);equal(Ledger.totals(merged).stock(),19L);equal(Ledger.merge(merged,original).size(),3);});
        test("restore conflicting IDs rejects without changing records",()->{var a=add(opening(),sale("conflicting-001","single","cash",350,0));var b=add(opening(),sale("conflicting-001","single","cash",400,0));reject(()->Ledger.merge(a,b));equal(a.get(2).revenue(),350L);equal(a.size(),3);});
        test("restore incompatible independent stock histories rejected",()->{var a=add(opening(),stock("branch-a-00001","missing",15,0));var b=add(opening(),stock("branch-b-00001","lost",10,0));reject(()->Ledger.merge(a,b));});
        test("corrupted checksum and truncated backup rejected",()->{String encoded=Backup.encode(data(opening()));reject(()->Backup.decode(encoded.replace("Opening purchase","Changed purchase")));reject(()->Backup.decode(encoded.substring(0,encoded.length()-3)));});
        test("incorrect version and currency rejected",()->{var root=signedRoot(Backup.encode(data(opening())));root.put("version",2L);String changed=resign(root);reject(()->Backup.decode(changed));root.put("version",1L);root.put("currency","USD");String usd=resign(root);reject(()->Backup.decode(usd));});
        test("opening mutation and missing opening rejected",()->{var es=opening();es.set(0,stock(Ledger.OPEN_PURCHASE,"restock",25,5000));reject(()->Ledger.validateAll(es));reject(()->Ledger.validateAll(Ledger.list(opening().get(1))));});
        test("invalid backup timestamp and amounts rejected even with checksum",()->{var root=signedRoot(Backup.encode(data(opening())));@SuppressWarnings("unchecked") var entries=(List<Object>)root.get("events");@SuppressWarnings("unchecked") var first=(Map<String,Object>)entries.get(0);first.put("timestamp","invented date");String bad=resign(root);reject(()->Backup.decode(bad));first.put("timestamp",null);first.put("cost",-1L);String negative=resign(root);reject(()->Backup.decode(negative));});
        test("duplicate JSON keys and invalid numeric syntax rejected",()->{reject(()->Json.parse("{\"x\":1,\"x\":2}"));reject(()->Json.parse("[1.2]"));reject(()->Json.parse("[01]"));reject(()->Json.parse("{\"x\":null}garbage"));reject(()->Json.parse("[1,]"));});
        test("CSV retains correction IDs and escapes notes",()->{var e=new Ledger.Event("csv-sale-00001",NOW,NOW,"single",1,"cash",350,0,0,"=SUM(A1)\n\"quoted\"",null);var es=add(add(opening(),e),undo("csv-undo-00001",e.id()));String csv=Backup.csv(es);if(!csv.contains("\"3.50\"")||!csv.contains("\"'=" )||!csv.contains("\"\"quoted\"\"")||!csv.contains("csv-undo-00001"))throw new AssertionError(csv);});
        test("large backup validation uses bounded iterative state",()->{var es=opening();for(int i=0;i<2000;i++)es.add(stock("large-stock-"+i,"restock",1,1));Ledger.validateAll(es);var decoded=Backup.decode(Backup.encode(data(es)));equal(decoded.events().size(),2002);equal(Ledger.totals(decoded.events()).stock(),2020L);});
        List<Object> parity=new ArrayList<>();
        for(int i=0;i<100;i++){
            var es=add(add(add(opening(),sale("parity-single-"+i,"single","cash",350+i,0)),sale("parity-deal-"+i,"deal","card",600+i,i)),stock("parity-stock-"+i,"restock",6,1800+i));
            es=add(es,stock("parity-missing-"+i,"missing",3,0));
            if(i%2==0)es=add(es,undo("parity-undo-"+i,"parity-deal-"+i));
            if(i%3==0)es=add(es,undo("parity-opening-"+i,Ledger.OPEN_MISSING));
            var t=Ledger.totals(es);Map<String,Object> values=new LinkedHashMap<>();
            values.put("stock",t.stock());values.put("singles",t.singles());values.put("deals",t.deals());values.put("missing",t.missing());values.put("revenue",t.revenue());values.put("cash",t.cash());values.put("card",t.card());values.put("fees",t.fees());values.put("purchases",t.purchases());values.put("result",t.result());
            List<Object> eventRows=new ArrayList<>();for(var e:es)eventRows.add(Backup.eventMap(e));
            Map<String,Object> scenario=new LinkedHashMap<>();scenario.put("events",eventRows);scenario.put("totals",values);parity.add(scenario);
        }
        Files.writeString(Path.of(".build/parity.json"),Json.write(parity),StandardCharsets.UTF_8);
        var fixture=add(opening(),sale("host-fixture-01","deal","card",600,25));Files.writeString(Path.of(".build/host-backup.json"),Backup.encode(data(fixture)),StandardCharsets.UTF_8);
        System.out.println("CORE RESULTS: "+passed+" passed, "+failed+" failed.");if(failed>0)throw new AssertionError(failed+" core checks failed");
    }
}
