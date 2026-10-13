package au.monster.tracker;
import android.content.*;
import android.security.keystore.*;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;
import java.security.KeyStore;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Scheduled backup password is wrapped by a device-only Keystore key, never included in backups. */
public final class BackupSettings {
    private static final String ALIAS="monster-scheduled-backup-secret-v1";
    private final android.content.SharedPreferences preferences;
    public BackupSettings(Context context){preferences=context.getSharedPreferences("backup-settings",Context.MODE_PRIVATE);}
    private SecretKey key()throws Exception{KeyStore ks=KeyStore.getInstance("AndroidKeyStore");ks.load(null);if(!ks.containsAlias(ALIAS)){KeyGenerator generator=KeyGenerator.getInstance("AES","AndroidKeyStore");generator.init(new KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());generator.generateKey();}return (SecretKey)ks.getKey(ALIAS,null);}
    public boolean enabled(){return preferences.getBoolean("enabled",false);}public boolean configured(){return preferences.contains("secret");}public int hours(){return preferences.getInt("hours",24);}public String folder(){return preferences.getString("folder","");}public String status(){return preferences.getString("status","No automatic backup has run yet.");}
    public void savePassword(char[] password)throws Exception{EncryptedBackup.password(password);Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,key());byte[] plain=new String(password).getBytes(StandardCharsets.UTF_8);try{String encrypted=Base64.getEncoder().encodeToString(cipher.doFinal(plain));if(!preferences.edit().putString("secret",encrypted).putString("iv",Base64.getEncoder().encodeToString(cipher.getIV())).commit())throw new IllegalStateException("Backup password could not be saved.");}finally{Arrays.fill(plain,(byte)0);}}
    public char[] password()throws Exception{if(!configured())throw new IllegalStateException("Set the scheduled-backup password first.");Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,key(),new GCMParameterSpec(128,Base64.getDecoder().decode(preferences.getString("iv",""))));byte[] plain=cipher.doFinal(Base64.getDecoder().decode(preferences.getString("secret","")));try{return new String(plain,StandardCharsets.UTF_8).toCharArray();}finally{Arrays.fill(plain,(byte)0);}}
    public void schedule(boolean enabled,int hours){if(enabled&&!configured())throw new IllegalStateException("Set a backup password before enabling the schedule.");if(hours!=24&&hours!=168)throw new IllegalArgumentException("Choose daily or weekly backups.");if(!preferences.edit().putBoolean("enabled",enabled).putInt("hours",hours).commit())throw new IllegalStateException("Schedule could not be saved.");}
    public void folder(String uri){if(!preferences.edit().putString("folder",uri).commit())throw new IllegalStateException("Folder could not be saved.");}
    public void status(String value){preferences.edit().putString("status",value).commit();}
}
