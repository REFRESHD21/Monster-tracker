package au.monster.tracker;
import java.util.*;
import java.nio.file.*;
public final class ParityFixtures {
 public static void main(String[] args)throws Exception {
  List<Object> cases=new ArrayList<>();long now=1791979200000L;
  for(int scenario=0;scenario<100;scenario++) {
   List<Ledger.Event> e=new ArrayList<>(Ledger.opening(now));Random random=new Random(scenario);List<Ledger.Event> singles=new ArrayList<>();
   for(int n=0;n<30;n++) {long stock=Ledger.totals(e).stock();String type=stock<3?"restock":switch(random.nextInt(5)){case 0->"restock";case 1->"missing";case 2->"damaged";case 3->"single";default->"deal";};long q=type.equals("restock")?1+random.nextInt(20):type.equals("deal")?2:1;
    var event=new Ledger.Event("fixture-event-"+scenario+"-"+n,now+n*1000,now+n*1000,type,q,type.equals("single")||type.equals("deal")?"card":"none",type.equals("single")?350:type.equals("deal")?600:0,type.equals("single")?7:type.equals("deal")?11:0,type.equals("restock")?q*173+random.nextInt(10):0,"Fixture",null);Ledger.validate(event,e);e.add(event);if(type.equals("single"))singles.add(event);
   }
   if(!singles.isEmpty()){var original=singles.get(0);e.add(new Ledger.Event("fixture-correction-"+scenario,now+50000,now+50000,"undo",0,"none",0,0,0,"Correction",original.id()));}
   var result=Finance.calculate(e,new HashMap<>(),new ArrayList<>(),new ArrayList<>(),new ArrayList<>(),new HashMap<>());var summary=Finance.summarize(result,Finance.period("all",java.time.LocalDate.of(2026,10,14)));Map<String,Object> expected=new LinkedHashMap<>();expected.put("revenue",summary.revenue());expected.put("cash",summary.cash());expected.put("card",summary.card());expected.put("fees",summary.fees());expected.put("purchases",summary.purchases());expected.put("cogs",summary.cogs());expected.put("losses",summary.losses());expected.put("netProfit",summary.netProfit());expected.put("inventoryValue",summary.inventoryValue());expected.put("stock",Ledger.totals(e).stock());
   Map<String,Object> c=new LinkedHashMap<>();c.put("backup",Json.parse(Backup.encode(new Backup.Data(e,new Ledger.Prices(350,600)))));c.put("expected",expected);cases.add(c);
  }
  Files.createDirectories(Path.of("universal/test/fixtures"));Files.writeString(Path.of("universal/test/fixtures/java-parity.json"),Json.write(cases));System.out.println("Wrote 100 Java accounting oracle cases.");
 }
}
