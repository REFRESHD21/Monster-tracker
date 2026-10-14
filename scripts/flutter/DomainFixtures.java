package au.monster.tracker;
import java.util.*;import java.nio.file.*;import java.nio.charset.StandardCharsets;
public final class DomainFixtures {
 static long n=1791979200000L;
 static Ledger.Event e(String id,String type,long q,long rev,long fee,long cost,String target,long offset){return new Ledger.Event(id,n+offset,n+offset,type,q,type.equals("deal")?"card":"none",rev,fee,cost,"Domain fixture",target);}
 public static void main(String[] args)throws Exception {
  List<Ledger.Event> events=new ArrayList<>(Ledger.opening(n));
  var purchase=e("domain-purchase-001","restock",5,0,0,1001,null,1000);events.add(purchase);
  var sale=e("domain-sale-00001","deal",2,600,25,0,null,2000);events.add(sale);
  events.add(e("domain-missing-001","missing",1,0,0,0,null,3000));
  var returned=e("domain-return-001","restock",1,0,0,0,null,4000);events.add(returned);
  var product=new Catalog.Product("domain-product-001","Skincare",3,12,5,1001,"Supplier");
  var legacy=new Catalog.Product(Catalog.LEGACY,"Unassigned historical stock",0,0,1,0,"");
  Map<String,List<Catalog.Allocation>> allocations=new LinkedHashMap<>();for(var e:events)if(!e.id().startsWith("opening-"))allocations.put(e.id(),Ledger.list(new Catalog.Allocation(product.id(),e.quantity())));
  var transfer=new Catalog.Transfer("domain-transfer-001",Catalog.LEGACY,product.id(),10,n,"Identify stock",Ledger.OPEN_MISSING);
  var receipt=Purchases.receipt("%PDF-1.4\noriginal supplier receipt\n".getBytes(StandardCharsets.UTF_8));
  var line=new Purchases.Line("domain-line-0001","Skincare",5,1,1001,91,true,product.id());
  var invoice=new Purchases.Document("domain-invoice-001","purchase","Supplier","INV-001",null,n,1001,91,"Stock","",receipt.hash(),Ledger.list(line));
  var expense=new Purchases.Document("domain-expense-001","expense","Shop","",null,n,1100,100,"Travel","Unknown date",null,Ledger.list());
  Map<String,Object> cancellation=new LinkedHashMap<>();cancellation.put("id","domain-cancel-0001");cancellation.put("documentId",expense.id());cancellation.put("recordedAt",n+5000);cancellation.put("note","Entry mistake");
  var request=new Refunds.Request("domain-refund-0001",sale.id(),300,n+3000,"Partial refund",false);
  var ok=new Refunds.Observation("domain-observed-001",request.id(),"manual-"+request.id(),"succeeded",null,n+3500,3L,"");
  var failed=new Refunds.Observation("domain-observed-002",request.id(),"manual-"+request.id(),"failed",null,n+6000,0L,"Corrected");
  var goods=new Refunds.Return("domain-goods-0001",request.id(),returned.id(),1,returned.recordedAt());
  var taxes=Map.of(purchase.id(),new Finance.Tax(true,91,91,0),sale.id(),new Finance.Tax(true,0,0,55),expense.id(),new Finance.Tax(true,100,100,0));
  Map<String,Object> catalog=new LinkedHashMap<>();catalog.put("products",Ledger.list(productMap(legacy),productMap(product)));catalog.put("barcodes",Ledger.list(Map.of("code","0012345","productId",product.id()),Map.of("code","0098765","productId",product.id())));catalog.put("allocations",allocations.entrySet().stream().map(a->Map.of("eventId",a.getKey(),"allocations",Catalog.allocationMaps(a.getValue()))).toList());catalog.put("transfers",Ledger.list(Catalog.transferMap(transfer)));
  Map<String,Object> business=new LinkedHashMap<>();business.put("catalog",catalog);business.put("documents",Ledger.list(Purchases.documentMap(invoice),Purchases.documentMap(expense)));business.put("receipts",Ledger.list(Map.of("hash",receipt.hash(),"mime",receipt.mime(),"content",Base64.getEncoder().encodeToString(receipt.content()))));business.put("deliveries",Ledger.list(Map.of("id","domain-delivery-001","lineId",line.id(),"eventId",purchase.id(),"quantity",5L,"cost",1001L,"timestamp",purchase.timestamp(),"recordedAt",purchase.recordedAt(),"note","Received")));business.put("cancellations",Ledger.list(cancellation));business.put("audit",Ledger.list());
  List<Object> taxRows=new ArrayList<>();for(var t:taxes.entrySet())taxRows.add(Map.of("id",t.getKey(),"kind",t.getKey().equals(expense.id())?"document":"ledger","tax",FinanceBackup.taxMap(t.getValue())));
  business.put("finance",Map.of("settings",Map.of("gst",Map.of("registered",true,"expenseCredits",true),"product:"+product.id(),Map.of("treatment","taxable")),"taxes",taxRows));
  business.put("refunds",Map.of("requests",Ledger.list(Refunds.requestMap(request)),"observations",Ledger.list(Refunds.observationMap(ok),Refunds.observationMap(failed)),"returns",Ledger.list(Refunds.returnMap(goods))));
  var photos=Ledger.list(Receipts.photo(sale.id(),new byte[]{(byte)255,(byte)216,(byte)255,(byte)217}));
  String backup=Backup.encode(new Backup.Data(events,new Ledger.Prices(350,600),photos,business));Backup.decode(backup);
  var result=Finance.calculate(events,allocations,Ledger.list(transfer),Ledger.list(invoice,expense),Ledger.list(cancellation),taxes,Map.of(returned.id(),sale.id()));var rows=new ArrayList<>(result.rows());rows.addAll(Refunds.financialRows(Ledger.list(request),Ledger.list(ok,failed),events,taxes,allocations));var totals=Finance.summarize(new Finance.Result(rows,result.inventoryValue()),Finance.period("all",java.time.LocalDate.of(2026,10,14)));
  Map<String,Object> expected=new LinkedHashMap<>();expected.put("revenue",totals.revenue());expected.put("fees",totals.fees());expected.put("cogs",totals.cogs());expected.put("losses",totals.losses());expected.put("expenses",totals.expenses());expected.put("inputGst",totals.inputGst());expected.put("outputGst",totals.outputGst());expected.put("netProfit",totals.netProfit());expected.put("inventoryValue",totals.inventoryValue());
  Files.writeString(Path.of("universal/test/fixtures/full-domain.json"),Json.write(Map.of("backup",Json.parse(backup),"expected",expected)));
  Files.writeString(Path.of("universal/test/fixtures/legacy-encrypted.txt"),Base64.getEncoder().encodeToString(EncryptedBackup.encrypt(backup.getBytes(StandardCharsets.UTF_8),"fixture-password-123".toCharArray())));
  List<Object> versions=new ArrayList<>();for(int v=1;v<=6;v++){var root=new LinkedHashMap<>(Purchases.map(Json.parse(backup)));root.put("version",(long)v);if(v<6){var b=new LinkedHashMap<>(business);b.remove("refunds");if(v<5)b.remove("finance");if(v<4)b.remove("catalog");if(v>=3){if(v<4){b.put("documents",Ledger.list());b.put("receipts",Ledger.list());b.put("deliveries",Ledger.list());b.put("cancellations",Ledger.list());}root.put("business",b);}else root.remove("business");}if(v<2)root.remove("receipts");root.remove("sha256");root.put("sha256",Purchases.hash(Json.write(root).getBytes(StandardCharsets.UTF_8)));Backup.decode(Json.write(root));versions.add(root);}
  Files.writeString(Path.of("universal/test/fixtures/legacy-versions.json"),Json.write(versions));
  System.out.println("Generated Java-validated backup versions 1–6, full-domain accounting and encrypted migration fixture.");
 }
 static Map<String,Object> productMap(Catalog.Product p){return Map.of("id",p.id(),"name",p.name(),"minimum",p.minimum(),"target",p.target(),"packSize",p.packSize(),"packCost",p.packCost(),"supplier",p.supplier());}
}
