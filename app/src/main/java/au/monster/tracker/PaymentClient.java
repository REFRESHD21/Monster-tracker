package au.monster.tracker;
import java.net.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public final class PaymentClient {
    private final PaymentSettings settings;
    public PaymentClient(PaymentSettings settings){this.settings=settings;}
    @SuppressWarnings("unchecked") public Map<String,Object> post(String path,Map<String,Object> body)throws Exception {
        if(!settings.configured())throw new IllegalStateException("Set up Stripe in Settings first.");
        HttpURLConnection c=(HttpURLConnection)new URL(settings.url()+path).openConnection();c.setInstanceFollowRedirects(false);c.setRequestMethod("POST");c.setConnectTimeout(15000);c.setReadTimeout(35000);c.setDoOutput(true);c.setRequestProperty("Content-Type","application/json");c.setRequestProperty("Authorization","Bearer "+settings.token());
        try{try(OutputStream out=c.getOutputStream()){out.write(Json.write(body).getBytes(StandardCharsets.UTF_8));}int code=c.getResponseCode();InputStream stream=code>=200&&code<300?c.getInputStream():c.getErrorStream();if(stream==null)throw new IOException("Payment service unavailable. Retry the same payment.");String text;try(InputStream in=stream;ByteArrayOutputStream out=new ByteArrayOutputStream()){byte[] b=new byte[4096];int n;while((n=in.read(b))!=-1){if(out.size()+n>65536)throw new IOException("Invalid payment service response.");out.write(b,0,n);}text=out.toString("UTF-8");}Object parsed=Json.parse(text);if(!(parsed instanceof Map<?,?>))throw new IOException("Invalid payment service response.");Map<String,Object> response=(Map<String,Object>)parsed;if(code<200||code>=300)throw new IOException(response.get("error") instanceof String s?s:"Payment service unavailable. Retry the same payment.");return response;}finally{c.disconnect();}
    }
    public Map<String,Object> sale(String path,Ledger.Event event)throws Exception{Map<String,Object> body=new LinkedHashMap<>();body.put("saleId",event.id());body.put("amount",event.revenue());return post(path,body);}
}
