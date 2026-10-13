package au.monster.tracker;
import java.util.*;
import java.nio.charset.StandardCharsets;
public final class EncryptedBackupTests {
    private static int passed;
    interface Check{void run()throws Exception;}
    private static void test(String name,Check c)throws Exception{c.run();passed++;System.out.println("PASS "+name);}
    private static void reject(Check c)throws Exception{try{c.run();throw new AssertionError("Invalid encrypted backup accepted");}catch(java.security.GeneralSecurityException|java.io.IOException|IllegalArgumentException expected){}}
    private static void check(boolean b){if(!b)throw new AssertionError("Condition failed");}
    public static void main(String[] args)throws Exception{char[] password="test password stored elsewhere".toCharArray();var data=new Backup.Data(Ledger.opening(System.currentTimeMillis()),new Ledger.Prices(350,600));byte[] plain=Backup.encode(data).getBytes(StandardCharsets.UTF_8),encrypted=EncryptedBackup.encrypt(plain,password);
        test("portable encrypted backup preserves opening unknown dates",()->{var restored=EncryptedBackup.decode(encrypted,password);check(restored.events().get(1).timestamp()==null);check(Ledger.totals(restored.events()).stock()==20);});
        test("each encryption uses random salt and nonce",()->check(!Arrays.equals(encrypted,EncryptedBackup.encrypt(plain,password))));
        test("wrong password cannot decrypt or modify data",()->reject(()->EncryptedBackup.decode(encrypted,"wrong long password".toCharArray())));
        test("damaged encrypted payload fails authentication",()->{var changed=encrypted.clone();changed[changed.length-1]^=1;reject(()->EncryptedBackup.decode(changed,password));});
        test("modified salt and metadata fail authentication",()->{var changed=encrypted.clone();changed[20]^=1;reject(()->EncryptedBackup.decode(changed,password));});
        test("truncated and invalid files rejected",()->{reject(()->EncryptedBackup.decode(Arrays.copyOf(encrypted,encrypted.length-1),password));reject(()->EncryptedBackup.decode(new byte[100],password));});
        test("untrusted work factor rejected before expensive decryption",()->{var changed=encrypted.clone();changed[11]=(byte)0x7f;reject(()->EncryptedBackup.decode(changed,password));});
        test("weak password and decrypted invalid JSON rejected",()->{reject(()->EncryptedBackup.encrypt(plain,"short".toCharArray()));var invalid=EncryptedBackup.encrypt("not a backup".getBytes(StandardCharsets.UTF_8),password);reject(()->EncryptedBackup.decode(invalid,password));});
        System.out.println("ENCRYPTED BACKUP RESULTS: "+passed+" passed, 0 failed.");
    }
}
