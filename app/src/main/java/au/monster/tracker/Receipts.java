package au.monster.tracker;

import java.util.*;
import java.security.MessageDigest;

/** Receipt bytes travel with the backup; paths and document-provider URIs never do. */
public final class Receipts {
    public static final int MAX_PHOTO_BYTES=1024*1024, MAX_TOTAL_BYTES=24*1024*1024, MAX_COUNT=100;
    public record Photo(String id,String eventId,long createdAt,String mime,String base64,String sha256) {}
    public static Photo photo(String eventId,byte[] bytes){return new Photo(Ledger.id(),eventId,System.currentTimeMillis(),"image/jpeg",Base64.getEncoder().encodeToString(bytes),hash(bytes));}
    public static byte[] bytes(Photo p){try{return Base64.getDecoder().decode(p.base64());}catch(IllegalArgumentException e){throw new IllegalArgumentException("Invalid receipt image encoding.");}}
    public static String hash(byte[] b){try{StringBuilder s=new StringBuilder();for(byte x:MessageDigest.getInstance("SHA-256").digest(b))s.append(String.format("%02x",x&255));return s.toString();}catch(Exception e){throw new IllegalStateException(e);}}
    public static void validate(List<Photo> photos,List<Ledger.Event> events){
        if(photos.size()>MAX_COUNT)throw new IllegalArgumentException("Receipt limit reached: 100 photos. Export a backup.");
        Set<String> eventIds=new HashSet<>(),ids=new HashSet<>();for(var e:events)eventIds.add(e.id());
        long total=0;
        for(var p:photos){
            if(p.id()==null||!p.id().matches("[A-Za-z0-9-]{8,80}")||!ids.add(p.id())||!eventIds.contains(p.eventId())||p.createdAt()<0||!"image/jpeg".equals(p.mime())||p.base64()==null||p.base64().length()>((MAX_PHOTO_BYTES+2)/3)*4)throw new IllegalArgumentException("Invalid receipt or transaction reference.");
            byte[] b=bytes(p);total+=b.length;
            if(b.length<4||b.length>MAX_PHOTO_BYTES||b[0]!=(byte)0xff||b[1]!=(byte)0xd8||b[b.length-2]!=(byte)0xff||b[b.length-1]!=(byte)0xd9||!hash(b).equals(p.sha256())||!Base64.getEncoder().encodeToString(b).equals(p.base64()))throw new IllegalArgumentException("Receipt image checksum or format failed.");
        }
        if(total>MAX_TOTAL_BYTES)throw new IllegalArgumentException("Receipt storage limit reached: 24 MB. Export a backup.");
    }
    public static List<Photo> merge(List<Photo> current,List<Photo> incoming,List<Ledger.Event> events){Map<String,Photo> all=new LinkedHashMap<>();for(var p:current)all.put(p.id(),p);for(var p:incoming){var old=all.putIfAbsent(p.id(),p);if(old!=null&&!old.equals(p))throw new IllegalArgumentException("Receipt ID conflict. Nothing was changed.");}var result=new ArrayList<>(all.values());validate(result,events);return Ledger.copy(result);}
    public static Map<String,Object> map(Photo p){Map<String,Object> m=new LinkedHashMap<>();m.put("id",p.id());m.put("eventId",p.eventId());m.put("createdAt",p.createdAt());m.put("mime",p.mime());m.put("base64",p.base64());m.put("sha256",p.sha256());return m;}
    public static Photo parse(Object value){if(!(value instanceof Map<?,?> m)||!m.keySet().equals(Ledger.set("id","eventId","createdAt","mime","base64","sha256")))throw new IllegalArgumentException("Invalid receipt fields.");try{return new Photo((String)m.get("id"),(String)m.get("eventId"),(Long)m.get("createdAt"),(String)m.get("mime"),(String)m.get("base64"),(String)m.get("sha256"));}catch(RuntimeException e){throw new IllegalArgumentException("Invalid receipt values.");}}
    private Receipts(){}
}
