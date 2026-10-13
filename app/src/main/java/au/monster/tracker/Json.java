package au.monster.tracker;

import java.util.*;

/** Small strict JSON codec for local backups; duplicate keys, excessive depth and non-integer numbers are rejected. */
public final class Json {
    public static String write(Object v) {
        if(v==null)return "null";
        if(v instanceof String s){StringBuilder b=new StringBuilder("\"");for(int i=0;i<s.length();i++){char c=s.charAt(i);switch(c){case '"'->b.append("\\\"");case '\\'->b.append("\\\\");case '\n'->b.append("\\n");case '\r'->b.append("\\r");case '\t'->b.append("\\t");default->{if(c<32)b.append(String.format("\\u%04x",(int)c));else b.append(c);}}}return b.append('"').toString();}
        if(v instanceof Long || v instanceof Integer || v instanceof Boolean)return v.toString();
        if(v instanceof List<?> list){StringJoiner j=new StringJoiner(",","[","]");for(Object x:list)j.add(write(x));return j.toString();}
        if(v instanceof Map<?,?> map){TreeMap<String,Object> sorted=new TreeMap<>();for(var e:map.entrySet())sorted.put((String)e.getKey(),e.getValue());StringJoiner j=new StringJoiner(",","{","}");for(var e:sorted.entrySet())j.add(write(e.getKey())+":"+write(e.getValue()));return j.toString();}
        throw new IllegalArgumentException("Unsupported JSON value.");
    }
    public static Object parse(String input){Parser p=new Parser(input);Object v=p.value(0);p.space();if(p.i!=input.length())p.bad();return v;}
    private static final class Parser {
        final String s;int i;
        Parser(String s){if(s.length()>Backup.MAX_BYTES)throw new IllegalArgumentException("Backup exceeds 64 MB.");this.s=s;}
        void space(){while(i<s.length()&&" \t\r\n".indexOf(s.charAt(i))>=0)i++;}
        void bad(){throw new IllegalArgumentException("Invalid JSON near character "+i+".");}
        char take(){if(i>=s.length())bad();return s.charAt(i++);}
        boolean eat(char c){space();if(i<s.length()&&s.charAt(i)==c){i++;return true;}return false;}
        Object value(int depth){if(depth>32)throw new IllegalArgumentException("JSON nesting is too deep.");space();if(i>=s.length())bad();char c=s.charAt(i);
            if(c=='"')return string();
            if(c=='{'){i++;Map<String,Object> m=new LinkedHashMap<>();if(eat('}'))return m;do{space();if(i>=s.length()||s.charAt(i)!='"')bad();String key=string();if(!eat(':')||m.containsKey(key))bad();m.put(key,value(depth+1));}while(eat(','));if(!eat('}'))bad();return m;}
            if(c=='['){i++;List<Object> a=new ArrayList<>();if(eat(']'))return a;do{if(a.size()>Ledger.MAX_EVENTS+100)throw new IllegalArgumentException("Too many JSON entries.");a.add(value(depth+1));}while(eat(','));if(!eat(']'))bad();return a;}
            for(String literal:Ledger.list("null","true","false"))if(s.startsWith(literal,i)){i+=literal.length();return literal.equals("null")?null:literal.equals("true");}
            int start=i;if(c=='-')i++;if(i>=s.length()||!Character.isDigit(s.charAt(i)))bad();if(s.charAt(i)=='0'){i++;if(i<s.length()&&Character.isDigit(s.charAt(i)))bad();}else while(i<s.length()&&s.charAt(i)>='0'&&s.charAt(i)<='9')i++;
            try{return Long.parseLong(s.substring(start,i));}catch(NumberFormatException ex){bad();return null;}
        }
        String string(){if(take()!='"')bad();StringBuilder b=new StringBuilder();while(i<s.length()){char c=take();if(c=='"')return b.toString();if(c<32)bad();if(c=='\\'){char e=take();switch(e){case '"','\\','/'->b.append(e);case 'b'->b.append('\b');case 'f'->b.append('\f');case 'n'->b.append('\n');case 'r'->b.append('\r');case 't'->b.append('\t');case 'u'->{if(i+4>s.length())bad();try{b.append((char)Integer.parseInt(s.substring(i,i+4),16));}catch(NumberFormatException ex){bad();}i+=4;}default->bad();}}else b.append(c);}bad();return null;}
    }
    private Json(){}
}
