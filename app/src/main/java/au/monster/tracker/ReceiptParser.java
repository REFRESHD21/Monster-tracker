package au.monster.tracker;

import java.time.*;
import java.util.*;
import java.util.regex.*;

/** Conservative receipt suggestions, never inventory writes. Every inferred value is reviewable. */
public final class ReceiptParser {
    public record Item(String description,long packs,long packSize,long total,Long unitPrice){}
    public record Suggestions(String supplier,String reference,Long date,Long total,Long gst,List<Item> items,String raw){}
    private static final Pattern MONEY=Pattern.compile("\\$?([0-9]{1,6}[.,][0-9]{2})\\b");
    public static Suggestions parse(String raw){String supplier="",reference="";Long date=null,total=null,gst=null;List<Item> items=new ArrayList<>();
        for(String original:raw.split("\\r?\\n")){String line=original.trim();if(line.isEmpty())continue;String lower=line.toLowerCase(Locale.ROOT);
            if(supplier.isEmpty()&&line.matches(".*[A-Za-z].*")&&!lower.matches(".*(?:tax invoice|receipt|invoice number|gst|abn|total|date).*"))supplier=line.length()>120?line.substring(0,120):line;
            Matcher ref=Pattern.compile("(?i)\\b(?:invoice|receipt|reference|ref)\\s*(?:no\\.?|number)?[\\s#:-]+([A-Za-z0-9/-]{2,60})").matcher(line);if(reference.isEmpty()&&ref.find()&&!ref.group(1).equalsIgnoreCase("date"))reference=ref.group(1);
            Matcher day=Pattern.compile("\\b([0-3]?[0-9])[/.-]([01]?[0-9])[/.-]((?:20)?[0-9]{2})\\b").matcher(line);if(date==null&&day.find())try{int year=Integer.parseInt(day.group(3));if(year<100)year+=2000;date=LocalDate.of(year,Integer.parseInt(day.group(2)),Integer.parseInt(day.group(1))).atStartOfDay(Ledger.PERTH).toInstant().toEpochMilli();}catch(DateTimeException ignored){}
            List<Long> prices=new ArrayList<>();Matcher amount=MONEY.matcher(line);int firstMoney=-1;while(amount.find()){try{long cents=Ledger.cents(amount.group(1).replace(',','.'));prices.add(cents);if(firstMoney<0)firstMoney=amount.start();}catch(IllegalArgumentException ignored){}}
            if(prices.isEmpty())continue;long last=prices.get(prices.size()-1);
            if(lower.matches(".*\\b(?:gst|tax)\\b.*")){gst=last;continue;}
            if(lower.matches("^(?:grand\\s+total|total|amount\\s+paid|amount\\s+due)\\b.*")){total=last;continue;}
            if(lower.matches(".*(?:subtotal|change|cash|card|eftpos|balance|discount|tender|rounding).*"))continue;
            if(firstMoney<=0||!line.substring(0,firstMoney).matches(".*[A-Za-z].*"))continue;String description=line.substring(0,firstMoney).trim();if(description.length()>120)description=description.substring(0,120);
            long packs=1,size=1;Matcher qty=Pattern.compile("(?i)(?:\\bqty\\s*[:=]?\\s*(\\d{1,4})\\b|\\b(\\d{1,4})\\s*[x×]\\b)").matcher(line);if(qty.find())packs=Long.parseLong(qty.group(1)==null?qty.group(2):qty.group(1));Matcher pack=Pattern.compile("(?i)\\b(\\d{1,3})\\s*(?:pk|pack|cans)\\b").matcher(line);if(pack.find())size=Long.parseLong(pack.group(1));if(packs>0&&size>0&&packs*size<=10000&&items.size()<100)items.add(new Item(description,packs,size,last,prices.size()>1?prices.get(0):null));
        }
        return new Suggestions(supplier,reference,date,total,gst,Ledger.copy(items),raw);
    }
    private ReceiptParser(){}
}
