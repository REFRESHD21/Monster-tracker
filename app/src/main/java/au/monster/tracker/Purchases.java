package au.monster.tracker;

import java.util.*;
import java.security.MessageDigest;
import java.nio.charset.StandardCharsets;

/** Offline supplier documents. Recording an invoice never constitutes receipt of goods. */
public final class Purchases {
    public static final int MAX_RECEIPT = 16*1024*1024;
    public record Line(String id,String product,long packs,long packSize,long cost,long gst,boolean stock) {
        public Line { checkId(id);text(product,120,false);if(packs<1||packs>10000||packSize<1||packSize>10000||packs*packSize>10000)bad("Line quantity must be 1–10,000 cans.");money(cost,gst); }
        public long cans(){return packs*packSize;}
    }
    public record Document(String id,String kind,String supplier,String reference,Long date,long recordedAt,
                           long amount,long gst,String category,String note,String receiptHash,List<Line> lines) {
        public Document {
            checkId(id);if(!Ledger.set("purchase","expense").contains(kind))bad("Unknown document type.");
            text(supplier,120,false);text(reference,120,true);text(category,80,true);text(note,500,true);money(amount,gst);
            if(recordedAt<946684800000L||recordedAt>4102444800000L||(date!=null&&(date<946684800000L||date>4102444800000L)))bad("Invalid document date.");
            if(receiptHash!=null&&!receiptHash.matches("[a-f0-9]{64}"))bad("Invalid receipt hash.");
            lines=Ledger.copy(lines);if(lines.size()>100)bad("A purchase may have at most 100 lines.");
            Set<String> ids=new HashSet<>();long sum=0,tax=0;for(Line l:lines){if(!ids.add(l.id))bad("Duplicate purchase line ID.");sum+=l.cost;tax+=l.gst;}
            if(kind.equals("purchase")&&(lines.isEmpty()||amount!=sum||gst!=tax))bad("Purchase total/GST must equal its lines.");
            if(kind.equals("expense")&&!lines.isEmpty())bad("Expense must not create stock lines.");
        }
        public String invoiceKey(){return reference.trim().isEmpty()?null:hash((supplier.trim().toLowerCase(Locale.ROOT)+"\n"+reference.trim().toLowerCase(Locale.ROOT)).getBytes(StandardCharsets.UTF_8));}
    }
    public record Receipt(String hash,String mime,byte[] content) {
        public Receipt { if(content.length==0||content.length>MAX_RECEIPT)bad("Receipt must be between 1 byte and 16 MB.");if(!hash.equals(Purchases.hash(content))||!mime.equals(Purchases.mime(content)))bad("Receipt data or file type is invalid.");content=content.clone(); }
        @Override public byte[] content(){return content.clone();}
    }
    public static Receipt receipt(byte[] bytes){return new Receipt(hash(bytes),mime(bytes),bytes);}
    public static String mime(byte[] bytes){if(bytes.length>=8&&Arrays.equals(Arrays.copyOf(bytes,8),new byte[]{(byte)137,80,78,71,13,10,26,10}))return "image/png";if(bytes.length>=3&&bytes[0]==(byte)255&&bytes[1]==(byte)216&&bytes[2]==(byte)255)return "image/jpeg";if(bytes.length>=5&&new String(bytes,0,5,StandardCharsets.US_ASCII).equals("%PDF-"))return "application/pdf";throw new IllegalArgumentException("Import an original JPG, PNG or PDF receipt.");}
    public static long allocatedCost(Line l,long receivedBefore,long receivedNow){if(!l.stock||receivedBefore<0||receivedNow<1||receivedBefore+receivedNow>l.cans())bad("Quantity exceeds this purchase's undelivered stock.");return (l.cost*(receivedBefore+receivedNow)/l.cans())-(l.cost*receivedBefore/l.cans());}
    public static Map<String,Object> lineMap(Line l){Map<String,Object> m=new LinkedHashMap<>();m.put("id",l.id);m.put("product",l.product);m.put("packs",l.packs);m.put("packSize",l.packSize);m.put("cost",l.cost);m.put("gst",l.gst);m.put("stock",l.stock);return m;}
    public static Map<String,Object> documentMap(Document d){Map<String,Object> m=new LinkedHashMap<>();m.put("id",d.id);m.put("kind",d.kind);m.put("supplier",d.supplier);m.put("reference",d.reference);m.put("date",d.date);m.put("recordedAt",d.recordedAt);m.put("amount",d.amount);m.put("gst",d.gst);m.put("category",d.category);m.put("note",d.note);m.put("receiptHash",d.receiptHash);List<Object> ls=new ArrayList<>();for(Line l:d.lines)ls.add(lineMap(l));m.put("lines",ls);return m;}
    public static Line line(Object value){Map<String,Object> m=map(value);if(!(m.get("stock") instanceof Boolean))bad("Invalid stock flag.");return new Line(str(m,"id"),str(m,"product"),num(m,"packs"),num(m,"packSize"),num(m,"cost"),num(m,"gst"),(Boolean)m.get("stock"));}
    public static Document document(Object value){Map<String,Object> m=map(value);List<Line> ls=new ArrayList<>();for(Object l:list(m.get("lines")))ls.add(line(l));return new Document(str(m,"id"),str(m,"kind"),str(m,"supplier"),str(m,"reference"),m.get("date")==null?null:num(m,"date"),num(m,"recordedAt"),num(m,"amount"),num(m,"gst"),str(m,"category"),str(m,"note"),m.get("receiptHash")==null?null:str(m,"receiptHash"),ls);}
    @SuppressWarnings("unchecked") public static Map<String,Object> map(Object v){if(!(v instanceof Map))bad("Expected a document object.");return (Map<String,Object>)v;}
    public static List<?> list(Object v){if(!(v instanceof List))bad("Expected a list.");return (List<?>)v;}
    public static String str(Map<String,Object> m,String k){Object v=m.get(k);if(!(v instanceof String))bad("Invalid text: "+k);return (String)v;}
    public static long num(Map<String,Object> m,String k){Object v=m.get(k);if(!(v instanceof Long))bad("Invalid whole-number field: "+k);return (Long)v;}
    public static void checkId(String id){if(id==null||!id.matches("[A-Za-z0-9-]{10,100}"))bad("Invalid record ID.");}
    private static void text(String s,int max,boolean empty){if(s==null||s.length()>max||(!empty&&s.trim().isEmpty()))bad("Missing or overly long document text.");}
    private static void money(long cost,long gst){Ledger.checkMoney(cost);if(gst<0||gst>cost)bad("GST must be between zero and the gross cost.");}
    public static String hash(byte[] bytes){try{byte[] h=MessageDigest.getInstance("SHA-256").digest(bytes);StringBuilder s=new StringBuilder();for(byte b:h)s.append(String.format(Locale.ROOT,"%02x",b&255));return s.toString();}catch(Exception e){throw new IllegalStateException(e);}}
    public static void bad(String message){throw new IllegalArgumentException(message);}
    private Purchases(){}
}
