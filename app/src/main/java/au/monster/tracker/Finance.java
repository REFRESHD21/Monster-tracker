package au.monster.tracker;

import java.time.*;
import java.util.*;

/** Deterministic, cents-exact FIFO derived from immutable ledger order, never current sale prices. */
public final class Finance {
    public record Tax(boolean registered,long actualGst,long inputGst,long outputGst){public Tax{Ledger.checkMoney(actualGst);Ledger.checkMoney(inputGst);Ledger.checkMoney(outputGst);if(inputGst>actualGst||(!registered&&(inputGst!=0||outputGst!=0)))Purchases.bad("Invalid historical GST snapshot.");}}
    public static final Tax UNTAXED=new Tax(false,0,0,0);
    public record Row(String id,String kind,Long date,String productId,long revenue,long cash,long card,long fees,long purchases,long expenses,long cogs,long losses,long outputGst,long inputGst,String note){public long netRevenue(){return revenue-outputGst;}public long grossProfit(){return netRevenue()-cogs;}public long netProfit(){return grossProfit()-fees-expenses-losses;}}
    public record Period(String label,Long from,Long to){public boolean includes(Long date){return from==null||date!=null&&date>=from&&date<to;}}
    public record Summary(long revenue,long cash,long card,long fees,long purchases,long expenses,long cogs,long losses,long outputGst,long inputGst,long grossProfit,long netProfit,long inventoryValue,long unknownDateRows,List<Row> rows,Map<String,Long> flavourProfit){}
    private static final class Lot{final String key,product;final long age;long quantity,cost;Lot(String key,String product,long age){this.key=key;this.product=product;this.age=age;}}
    private record Part(String key,String product,long age,long quantity,long cost){}
    private record Action(Ledger.Event event,List<Part> parts,List<Row> rows){}
    private static final class Book{
        final Map<String,Lot> lots=new LinkedHashMap<>();long age;
        void add(Part p){Lot l=lots.computeIfAbsent(p.key,k->new Lot(k,p.product,p.age));l.quantity+=p.quantity;l.cost+=p.cost;}
        List<Part> take(String product,long quantity,String preferred){List<Lot> available=new ArrayList<>();for(var l:lots.values())if(l.product.equals(product)&&l.quantity>0)available.add(l);available.sort(Comparator.<Lot>comparingInt(l->l.key.equals(preferred)?0:1).thenComparingLong(l->l.age));List<Part> parts=new ArrayList<>();long remaining=quantity;for(var lot:available){long q=Math.min(remaining,lot.quantity);if(q==0)continue;long cost=q==lot.quantity?lot.cost:lot.cost*q/lot.quantity;parts.add(new Part(lot.key,lot.product,lot.age,q,cost));lot.quantity-=q;lot.cost-=cost;remaining-=q;if(remaining==0)break;}if(remaining!=0)Purchases.bad("FIFO stock cannot be reconciled for "+product+". Existing records were not changed.");return parts;}
        void transfer(Catalog.Transfer t){for(var p:take(t.from(),t.quantity(),null)){String origin=p.key.substring(0,p.key.indexOf('|'));add(new Part(origin+"|"+t.to(),t.to(),p.age,p.quantity,p.cost));}}
        long value(){long result=0;for(var l:lots.values())result+=l.cost;return result;}
    }
    private static long cost(List<Part> parts){long cost=0;for(var p:parts)cost+=p.cost;return cost;}
    private static long share(long total,long cumulative,long quantity,long sum){return total*(cumulative+quantity)/sum-total*cumulative/sum;}
    public record Result(List<Row> rows,long inventoryValue){}
    public static Result calculate(List<Ledger.Event> events,Map<String,List<Catalog.Allocation>> allocations,List<Catalog.Transfer> transfers,List<Purchases.Document> documents,List<Map<String,Object>> cancellations,Map<String,Tax> taxes){
        return calculate(events,allocations,transfers,documents,cancellations,taxes,Collections.emptyMap());
    }
    private static List<Part> returnedParts(List<Part> original,long already,long quantity){List<Part> restored=new ArrayList<>();long remaining=quantity,skip=already;for(var p:original){long within=Math.min(skip,p.quantity);skip-=within;long qty=Math.min(remaining,p.quantity-within);if(qty>0){long value=p.cost*(within+qty)/p.quantity-p.cost*within/p.quantity;restored.add(new Part(p.key,p.product,p.age,qty,value));remaining-=qty;}if(remaining==0)break;}if(remaining!=0)Purchases.bad("Returned goods exceed the original costed sale.");return restored;}
    public static Result calculate(List<Ledger.Event> events,Map<String,List<Catalog.Allocation>> allocations,List<Catalog.Transfer> transfers,List<Purchases.Document> documents,List<Map<String,Object>> cancellations,Map<String,Tax> taxes,Map<String,String> returnedSales){
        Map<String,Long> received=new HashMap<>();
        Ledger.validateAll(events);Book book=new Book();Map<String,Action> history=new HashMap<>();List<Row> rows=new ArrayList<>();Map<String,Integer> positions=new HashMap<>();for(int i=0;i<events.size();i++)positions.put(events.get(i).id(),i);List<Catalog.Transfer> moves=new ArrayList<>(transfers);Map<String,Integer> anchors=new HashMap<>();for(var t:moves){int position=2;if(t.afterEventId()!=null){Integer source=positions.get(t.afterEventId());if(source==null)Purchases.bad("Missing FIFO transfer anchor.");position=Math.max(2,source+1);}else {position=events.size();for(int i=2;i<events.size();i++)if(t.recordedAt()<events.get(i).recordedAt()){position=i;break;}}anchors.put(t.id(),position);}moves.sort(Comparator.<Catalog.Transfer>comparingInt(t->anchors.get(t.id())).thenComparingLong(Catalog.Transfer::recordedAt));int next=0;
        for(int index=0;index<events.size();index++){
            var e=events.get(index);
            // Opening records always precede identified current stock. A transfer follows the last ledger
            // record present when it was made; newer transfers may carry an explicit ledger anchor.
            if(index>=2)while(next<moves.size()&&anchors.get(moves.get(next).id())<=index){book.transfer(moves.get(next++));}
            Tax tax=taxes.getOrDefault(e.id(),UNTAXED);List<Part> parts=new ArrayList<>();List<Row> eventRows=new ArrayList<>();
            if(e.type().equals("undo")){
                String returnedSale=returnedSales.get(e.target());if(returnedSale!=null){var source=history.get(e.target());received.put(returnedSale,received.getOrDefault(returnedSale,0L)-source.event.quantity());}Action original=history.get(e.target());if(original==null)Purchases.bad("Correction has no costing source.");
                if(original.event.type().equals("restock")){
                    for(var p:original.parts){var removed=book.take(p.product,p.quantity,p.key);parts.addAll(removed);}
                    long adjustment=cost(parts)-cost(original.parts);long cumulative=0;for(var r:original.rows){long quantity=0;for(var p:original.parts)if(p.product.equals(r.productId))quantity+=p.quantity;long difference=share(adjustment,cumulative,quantity,original.event.quantity());cumulative+=quantity;eventRows.add(reverse(e,r,difference));}
                }else{for(var p:original.parts)book.add(p);for(var r:original.rows)eventRows.add(reverse(e,r,0));}
            }else if(returnedSales.containsKey(e.id())){
                String sourceId=returnedSales.get(e.id());Action source=history.get(sourceId);if(source==null||!Ledger.set("single","deal").contains(source.event.type()))Purchases.bad("Returned goods need a prior costed sale.");long already=received.getOrDefault(sourceId,0L);parts=returnedParts(source.parts,already,e.quantity());received.put(sourceId,already+e.quantity());Map<String,Long> restoredQuantities=new HashMap<>();for(var p:parts){book.add(p);restoredQuantities.put(p.product,restoredQuantities.getOrDefault(p.product,0L)+p.quantity);}for(var a:Catalog.forEvent(e,allocations)){if(restoredQuantities.getOrDefault(a.productId(),0L)!=a.quantity())Purchases.bad("Returned flavour does not match the original sale.");long value=0;for(var p:parts)if(p.product.equals(a.productId()))value+=p.cost;eventRows.add(new Row(e.id(),"goods_return",e.timestamp(),a.productId(),0,0,0,0,0,0,-value,0,0,0,e.note()));}
            }else{
                long cumulative=0;for(var a:Catalog.forEvent(e,allocations)){
                    long revenue=share(e.revenue(),cumulative,a.quantity(),e.quantity()),fees=share(e.fee(),cumulative,a.quantity(),e.quantity()),purchase=share(e.cost(),cumulative,a.quantity(),e.quantity()),input=share(tax.inputGst(),cumulative,a.quantity(),e.quantity()),output=share(tax.outputGst(),cumulative,a.quantity(),e.quantity());
                    List<Part> used;long cogs=0,loss=0;
                    if(e.type().equals("restock")){var p=new Part(e.id()+"|"+a.productId(),a.productId(),book.age++,a.quantity(),purchase-input);book.add(p);used=Ledger.list(p);}
                    else{used=book.take(a.productId(),a.quantity(),null);if(e.type().equals("single")||e.type().equals("deal"))cogs=cost(used);else loss=cost(used);}
                    parts.addAll(used);eventRows.add(new Row(e.id(),e.type(),e.timestamp(),a.productId(),revenue,e.payment().equals("cash")?revenue:0,e.payment().equals("card")?revenue:0,fees,purchase,0,cogs,loss,output,input,e.note()));cumulative+=a.quantity();
                }
            }
            rows.addAll(eventRows);history.put(e.id(),new Action(e,parts,eventRows));
        }
        while(next<moves.size())book.transfer(moves.get(next++));
        Map<String,Row> expenseRows=new HashMap<>();for(var d:documents){long gross=0,gst=0;if(d.kind().equals("expense")){gross=d.amount();gst=d.gst();}else for(var l:d.lines())if(!l.stock()){gross+=l.cost();gst+=l.gst();}if(gross==0)continue;Tax tax=taxes.getOrDefault(d.id(),UNTAXED);if(tax.inputGst()>gst)Purchases.bad("Expense GST credit exceeds receipt GST.");var r=new Row(d.id(),"expense",d.date(),null,0,0,0,0,0,gross-tax.inputGst(),0,0,0,tax.inputGst(),d.category()+" · "+d.note());rows.add(r);expenseRows.put(d.id(),r);}
        for(var value:cancellations){var source=expenseRows.get(Purchases.str(value,"documentId"));if(source!=null){long time=Purchases.num(value,"recordedAt");rows.add(new Row(Purchases.str(value,"id"),"expense_correction",time,null,0,0,0,0,0,-source.expenses,0,0,0,-source.inputGst,Purchases.str(value,"note")));}}
        return new Result(Ledger.copy(rows),book.value());
    }
    private static Row reverse(Ledger.Event e,Row source,long additionalLoss){return new Row(e.id(),"correction",e.timestamp(),source.productId,-source.revenue,-source.cash,-source.card,-source.fees,-source.purchases,-source.expenses,-source.cogs,-source.losses+additionalLoss,-source.outputGst,-source.inputGst,e.note()+" · reverses "+source.id);}
    public static Summary summarize(Result result,Period period){long revenue=0,cash=0,card=0,fees=0,purchases=0,expenses=0,cogs=0,losses=0,output=0,input=0,unknown=0;List<Row> selected=new ArrayList<>();Map<String,Long> flavour=new LinkedHashMap<>();for(var r:result.rows){if(r.date==null)unknown++;if(!period.includes(r.date))continue;selected.add(r);revenue+=r.revenue;cash+=r.cash;card+=r.card;fees+=r.fees;purchases+=r.purchases;expenses+=r.expenses;cogs+=r.cogs;losses+=r.losses;output+=r.outputGst;input+=r.inputGst;if(r.productId!=null&&(r.kind.equals("single")||r.kind.equals("deal")||r.kind.equals("correction")||r.kind.equals("refund")||r.kind.equals("goods_return")))flavour.put(r.productId,flavour.getOrDefault(r.productId,0L)+r.grossProfit());}long gross=revenue-output-cogs;return new Summary(revenue,cash,card,fees,purchases,expenses,cogs,losses,output,input,gross,gross-fees-expenses-losses,result.inventoryValue,unknown,Ledger.copy(selected),Collections.unmodifiableMap(flavour));}
    public static Period period(String kind,LocalDate date){if(kind.equals("all"))return new Period("All recorded history (includes unknown dates)",null,null);LocalDate start,end;switch(kind){case "day"->{start=date;end=start.plusDays(1);}case "week"->{start=date.minusDays(date.getDayOfWeek().getValue()-1);end=start.plusWeeks(1);}case "month"->{start=date.withDayOfMonth(1);end=start.plusMonths(1);}case "quarter"->{start=LocalDate.of(date.getYear(),((date.getMonthValue()-1)/3)*3+1,1);end=start.plusMonths(3);}case "year"->{start=LocalDate.of(date.getYear(),1,1);end=start.plusYears(1);}case "financial_year"->{start=LocalDate.of(date.getMonthValue()<7?date.getYear()-1:date.getYear(),7,1);end=start.plusYears(1);}default->throw new IllegalArgumentException("Unknown reporting period.");}return new Period(start+" to "+end.minusDays(1)+" (Perth)",start.atStartOfDay(Ledger.PERTH).toInstant().toEpochMilli(),end.atStartOfDay(Ledger.PERTH).toInstant().toEpochMilli());}
    public static String csv(Summary s){StringBuilder out=new StringBuilder("id,type,perth_date,flavour_id,revenue_aud,cash_aud,card_aud,fees_aud,purchases_aud,expenses_ex_gst_aud,cogs_aud,stock_losses_aud,output_gst_aud,input_gst_aud,gross_profit_aud,estimated_net_profit_aud,note\r\n");for(var r:s.rows){String[] values={r.id,r.kind,Ledger.displayTime(r.date),r.productId==null?"":r.productId,Ledger.inputMoney(r.revenue),Ledger.inputMoney(r.cash),Ledger.inputMoney(r.card),Ledger.inputMoney(r.fees),Ledger.inputMoney(r.purchases),Ledger.inputMoney(r.expenses),Ledger.inputMoney(r.cogs),Ledger.inputMoney(r.losses),Ledger.inputMoney(r.outputGst),Ledger.inputMoney(r.inputGst),Ledger.inputMoney(r.grossProfit()),Ledger.inputMoney(r.netProfit()),r.note};for(int i=0;i<values.length;i++){if(i>0)out.append(',');String value=values[i];if(i==16&&!value.isEmpty()&&"=+-@".indexOf(value.charAt(0))>=0)value="'"+value;out.append('"').append(value.replace("\"","\"\"")).append('"');}out.append("\r\n");}return out.toString();}
    private Finance(){}
}
