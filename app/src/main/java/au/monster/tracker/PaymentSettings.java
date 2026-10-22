package au.monster.tracker;
import android.content.*;
import android.security.keystore.*;
import java.security.KeyStore;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;
import java.nio.charset.StandardCharsets;
import java.net.URI;
import java.util.Base64;

/** The device access token is encrypted using a non-exportable Android Keystore key. */
public final class PaymentSettings {
    private final String ALIAS;
    private final android.content.SharedPreferences prefs;
    public PaymentSettings(Context context){this(context,"payment-pairing");}
    PaymentSettings(Context context,String namespace){ALIAS=namespace.equals("payment-pairing")?"monster-payment-pairing-v1":"monster-"+namespace+"-v1";prefs=context.getSharedPreferences(namespace,Context.MODE_PRIVATE);}
    private javax.crypto.SecretKey key()throws Exception{KeyStore ks=KeyStore.getInstance("AndroidKeyStore");ks.load(null);if(!ks.containsAlias(ALIAS)){KeyGenerator g=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");g.init(new KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());g.generateKey();}return (javax.crypto.SecretKey)ks.getKey(ALIAS,null);}
    public String url(){return prefs.getString("url","");}public boolean live(){return prefs.getBoolean("live",false);}public boolean configured(){return !url().isEmpty()&&prefs.contains("token");}
    public void save(String url,String token,boolean live)throws Exception{URI uri=new URI(url.trim());if(!"https".equals(uri.getScheme())||uri.getHost()==null||uri.getUserInfo()!=null||uri.getQuery()!=null||uri.getFragment()!=null)throw new IllegalArgumentException("Use your payment backend's HTTPS address.");if(token.length()<32||token.startsWith("sk_")||token.startsWith("pk_"))throw new IllegalArgumentException("Enter the backend access token, not a Stripe API key.");Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,key());String encrypted=Base64.getEncoder().encodeToString(cipher.doFinal(token.getBytes(StandardCharsets.UTF_8)));if(!prefs.edit().putString("url",url.trim().replaceAll("/+$","")).putString("token",encrypted).putString("iv",Base64.getEncoder().encodeToString(cipher.getIV())).putBoolean("live",live).commit())throw new IllegalStateException("Could not save payment settings.");}
    public String token()throws Exception{Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,key(),new GCMParameterSpec(128,Base64.getDecoder().decode(prefs.getString("iv",""))));return new String(cipher.doFinal(Base64.getDecoder().decode(prefs.getString("token",""))),StandardCharsets.UTF_8);}
}
