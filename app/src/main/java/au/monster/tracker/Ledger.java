package au.monster.tracker;

import java.time.*;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.math.BigDecimal;
import java.math.RoundingMode;

/** Native port of provenance/original-ledger.mjs. All money is integer cents. */
public final class Ledger {
    public static final ZoneId PERTH = ZoneId.of("Australia/Perth");
    public static final int MAX_EVENTS = 10_000;
    public static final long MAX_MONEY = 10_000_000L;
    public static final String OPEN_PURCHASE = "opening-purchase-v1", OPEN_MISSING = "opening-missing-v1";
    private static final Set<String> TYPES = Ledger.set("single", "deal", "restock", "missing", "damaged", "lost", "undo");
    public record Event(String id, Long timestamp, long recordedAt, String type, long quantity,
                        String payment, long revenue, long fee, long cost, String note, String target) {
        public Event { Objects.requireNonNull(id); Objects.requireNonNull(type); Objects.requireNonNull(payment); Objects.requireNonNull(note); }
    }
    public record Prices(long single, long deal) {
        public Prices { checkMoney(single); checkMoney(deal); }
    }
    public record Totals(long stock, long singles, long deals, long missing, long revenue,
                         long cash, long card, long fees, long purchases) {
        public long result() { return revenue - fees - purchases; }
        public long sold() { return singles + deals * 2; }
    }
    public static List<Event> opening(long initializedAt) {
        return Ledger.list(new Event(OPEN_PURCHASE, null, initializedAt, "restock", 24, "none", 0, 0, 5000,
                                "Opening purchase; date unknown", null),
                       new Event(OPEN_MISSING, null, initializedAt, "missing", 4, "none", 0, 0, 0,
                                "Imported from existing Log row 2; date unknown", null));
    }
    public static Totals totals(List<Event> events) {
        Set<String> reversed = new HashSet<>();
        for (Event e : events) if (e.type.equals("undo")) reversed.add(e.target);
        long stock=0, singles=0, deals=0, missing=0, revenue=0, cash=0, card=0, fees=0, purchases=0;
        for (Event e : events) {
            if (e.type.equals("undo") || reversed.contains(e.id)) continue;
            if (e.type.equals("restock")) { stock+=e.quantity; purchases+=e.cost; }
            else {
                stock-=e.quantity;
                if (isLoss(e.type)) missing+=e.quantity;
                else {
                    if (e.type.equals("single")) singles++; else deals++;
                    revenue+=e.revenue; fees+=e.fee;
                    if (e.payment.equals("cash")) cash+=e.revenue; else card+=e.revenue;
                }
            }
        }
        return new Totals(stock,singles,deals,missing,revenue,cash,card,fees,purchases);
    }
    public static boolean isLoss(String type) { return Ledger.set("missing","damaged","lost").contains(type); }
    public static void checkMoney(long v) {
        if (v<0 || v>MAX_MONEY) throw new IllegalArgumentException("Amount must be between $0 and $100,000.");
    }
    public static long cents(String value) {
        try {
            long v = new BigDecimal(value.trim()).movePointRight(2).setScale(0,RoundingMode.UNNECESSARY).longValueExact();
            checkMoney(v); return v;
        } catch (ArithmeticException|NumberFormatException ex) { throw new IllegalArgumentException("Enter a valid AUD amount with at most two decimal places."); }
    }
    public static String money(long cents) { return String.format(Locale.forLanguageTag("en-AU"), "%s$%,.2f", cents<0?"−":"", Math.abs(cents)/100.0); }
    public static String inputMoney(long cents) { return BigDecimal.valueOf(cents,2).toPlainString(); }
    public static String displayTime(Long timestamp) {
        return timestamp == null ? "Date unknown" : DateTimeFormatter.ofPattern("d MMM yyyy · HH:mm:ss",Locale.ENGLISH).format(Instant.ofEpochMilli(timestamp).atZone(PERTH))+" Perth";
    }
    public static String iso(Long timestamp) { return timestamp==null?null:Instant.ofEpochMilli(timestamp).toString(); }
    public static String id() { return UUID.randomUUID().toString(); }
    public static Event event(String type,long quantity,String payment,long revenue,long fee,long cost,String note,Long timestamp,String target) {
        return new Event(id(),timestamp,System.currentTimeMillis(),type,quantity,payment,revenue,fee,cost,note,target);
    }
    private static final class ValidationState {
        final LinkedHashMap<String,Event> byId=new LinkedHashMap<>();
        final Set<String> undone=new HashSet<>();
        long stock;
        void apply(Event e){if(e.type.equals("undo")){Event source=byId.get(e.target);stock-=source.type.equals("restock")?source.quantity:-source.quantity;undone.add(e.target);}else stock+=e.type.equals("restock")?e.quantity:-e.quantity;byId.put(e.id,e);}
    }
    public static void validate(Event e,List<Event> before){ValidationState s=new ValidationState();for(Event old:before)s.apply(old);validate(e,s);}
    private static void validate(Event e,ValidationState before) {
        if (!e.id.matches("[A-Za-z0-9-]{10,100}")) fail("Invalid transaction ID.");
        if (before.byId.containsKey(e.id)) fail("Duplicate transaction ID.");
        if (!TYPES.contains(e.type)) fail("Unknown transaction type.");
        if (e.note.length()>500) fail("Note is limited to 500 characters.");
        checkMoney(e.revenue); checkMoney(e.fee); checkMoney(e.cost);
        long min = Instant.parse("2000-01-01T00:00:00Z").toEpochMilli();
        long max = Instant.parse("2100-01-01T00:00:00Z").toEpochMilli();
        if (e.recordedAt<min || e.recordedAt>max) fail("Invalid recorded timestamp.");
        boolean opening = e.id.equals(OPEN_PURCHASE)||e.id.equals(OPEN_MISSING);
        if (opening) {
            Event expected = opening(e.recordedAt).get(e.id.equals(OPEN_PURCHASE)?0:1);
            if (!e.equals(expected)) fail("Opening records must retain their original values and unknown dates.");
            if (e.id.equals(OPEN_PURCHASE) && !before.byId.isEmpty()) fail("Opening purchase must be first.");
            if (e.id.equals(OPEN_MISSING) && (before.byId.size()!=1 || !before.byId.containsKey(OPEN_PURCHASE))) fail("Opening adjustment must be second.");
            return;
        }
        if (before.byId.size()<2) fail("Opening records are missing.");
        if (e.timestamp==null || e.timestamp<min || e.timestamp>max) fail("Enter a valid transaction date.");
        if (e.type.equals("undo")) {
            Event source=before.byId.get(e.target);if(source==null)fail("Correction target does not exist.");
            if (source.type.equals("undo") || before.undone.contains(e.target)) fail("This transaction is already corrected or cannot be undone.");
            if (e.quantity!=0 || !e.payment.equals("none") || e.revenue!=0 || e.fee!=0 || e.cost!=0 || e.note.trim().isEmpty()) fail("Invalid correction. Add a reason.");
            long after=before.stock+(source.type.equals("restock")?-source.quantity:source.quantity);
            if (after<0) fail("Undo would make stock negative. Correct later stock deductions first.");
            return;
        }
        if (e.target!=null) fail("Only undo transactions may reference another record.");
        if (e.quantity<1 || e.quantity>10_000) fail("Quantity must be 1–10,000 cans.");
        if (e.type.equals("single")||e.type.equals("deal")) {
            if (e.quantity!=(e.type.equals("single")?1:2)) fail("Sale quantity does not match its type.");
            if (!Ledger.set("cash","card").contains(e.payment) || e.cost!=0 || e.fee>e.revenue || (e.payment.equals("cash")&&e.fee!=0)) fail("Invalid payment or fee. Cash fees must be zero; card fees cannot exceed revenue.");
        } else if (!e.payment.equals("none") || e.revenue!=0 || e.fee!=0 || (!e.type.equals("restock")&&e.cost!=0)) fail("Invalid stock transaction.");
        if (!e.type.equals("restock") && e.quantity>before.stock) fail("Not enough stock available.");
    }
    public static void validateAll(List<Event> events) {
        if (events.size()<2 || events.size()>MAX_EVENTS) fail("Invalid number of transactions.");
        if (!events.get(0).id.equals(OPEN_PURCHASE)||!events.get(1).id.equals(OPEN_MISSING)) fail("Required opening transactions are missing.");
        ValidationState history=new ValidationState();
        for (Event e:events) { validate(e,history); history.apply(e); }
    }
    public static boolean same(Event a, Event b) {
        // Opening ingestion time is device-local metadata, not the unknown historical date.
        if ((a.id.equals(OPEN_PURCHASE)||a.id.equals(OPEN_MISSING))&&a.id.equals(b.id))
            return a.equals(new Event(b.id,b.timestamp,a.recordedAt,b.type,b.quantity,b.payment,b.revenue,b.fee,b.cost,b.note,b.target));
        return a.equals(b);
    }
    public static List<Event> merge(List<Event> current,List<Event> incoming) {
        validateAll(incoming);
        validateAll(current);
        ValidationState context=new ValidationState();for(Event e:current)context.apply(e);
        ArrayList<Event> merged=new ArrayList<>(current);
        for(Event e:incoming) {
            Event old=context.byId.get(e.id);
            if(old!=null) { if(!same(old,e))fail("Conflicting transaction ID: "+e.id+". Nothing was restored."); }
            else { validate(e,context); merged.add(e); context.apply(e); }
        }
        if(merged.size()>MAX_EVENTS)fail("Transaction limit reached.");
        return Ledger.copy(merged);
    }
    private static void fail(String s) { throw new IllegalArgumentException(s); }
    @SafeVarargs public static <T> List<T> list(T... values){return Collections.unmodifiableList(Arrays.asList(values));}
    @SafeVarargs public static <T> Set<T> set(T... values){return Collections.unmodifiableSet(new HashSet<>(Arrays.asList(values)));}
    public static <T> List<T> copy(Collection<T> values){return Collections.unmodifiableList(new ArrayList<>(values));}
    private Ledger() {}
}
