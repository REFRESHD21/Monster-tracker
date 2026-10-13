package au.monster.tracker;

import javax.crypto.*;
import javax.crypto.spec.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.util.*;

/** Portable authenticated backup encryption; device Keystore is not the backup decryption key. */
public final class EncryptedBackup {
    private static final byte[] MAGIC="MONSTERBK1\n".getBytes(StandardCharsets.US_ASCII);
    public static final int ITERATIONS=310000,MAX_BYTES=Backup.MAX_BYTES+1024;
    private static SecretKey key(char[] password,byte[] salt,int iterations)throws GeneralSecurityException{PBEKeySpec spec=new PBEKeySpec(password,salt,iterations,256);try{return new SecretKeySpec(SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).getEncoded(),"AES");}finally{spec.clearPassword();}}
    public static void password(char[] password){if(password==null||password.length<10||password.length>200)throw new IllegalArgumentException("Use a backup password of 10–200 characters. Keep it outside this phone; it cannot be recovered if lost.");}
    public static byte[] encrypt(byte[] json,char[] password)throws GeneralSecurityException,IOException{password(password);if(json.length>Backup.MAX_BYTES)throw new IOException("Backup exceeds 64 MB.");byte[] salt=new byte[16],nonce=new byte[12];SecureRandom random=new SecureRandom();random.nextBytes(salt);random.nextBytes(nonce);ByteArrayOutputStream header=new ByteArrayOutputStream();try(DataOutputStream out=new DataOutputStream(header)){out.write(MAGIC);out.writeInt(ITERATIONS);out.write(salt);out.write(nonce);out.writeInt(json.length+16);}byte[] metadata=header.toByteArray();Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,key(password,salt,ITERATIONS),new GCMParameterSpec(128,nonce));cipher.updateAAD(metadata);ByteArrayOutputStream result=new ByteArrayOutputStream();result.write(metadata);result.write(cipher.doFinal(json));return result.toByteArray();}
    public static byte[] decrypt(byte[] file,char[] password)throws GeneralSecurityException,IOException{password(password);if(file.length>MAX_BYTES||file.length<MAGIC.length+4+16+12+4+16)throw new IOException("Invalid encrypted backup size.");try(DataInputStream in=new DataInputStream(new ByteArrayInputStream(file))){byte[] magic=new byte[MAGIC.length];in.readFully(magic);if(!Arrays.equals(magic,MAGIC))throw new IOException("Unsupported encrypted backup. Import ordinary JSON backups through the existing JSON restore option.");int iterations=in.readInt();if(iterations!=ITERATIONS)throw new IOException("Unsupported encryption settings; no data was changed.");byte[] salt=new byte[16],nonce=new byte[12];in.readFully(salt);in.readFully(nonce);int length=in.readInt(),headerLength=file.length-in.available();if(length<16||length>Backup.MAX_BYTES+16||length!=in.available())throw new IOException("Encrypted backup is truncated or has invalid lengths.");Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,key(password,salt,iterations),new GCMParameterSpec(128,nonce));cipher.updateAAD(Arrays.copyOf(file,headerLength));try{return cipher.doFinal(Arrays.copyOfRange(file,headerLength,file.length));}catch(AEADBadTagException e){throw new GeneralSecurityException("Wrong password or damaged backup. No records were changed.",e);}}}
    public static Backup.Data decode(byte[] file,char[] password)throws GeneralSecurityException,IOException{byte[] decoded=decrypt(file,password);try{return Backup.decode(new String(decoded,StandardCharsets.UTF_8));}finally{Arrays.fill(decoded,(byte)0);}}
    private EncryptedBackup(){}
}
