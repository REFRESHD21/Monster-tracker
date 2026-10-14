import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../core/codec.dart';
import '../core/legacy.dart';

class Backups {
  static final magic=utf8.encode('BUSINESSBK1\n'), legacyMagic=utf8.encode('MONSTERBK1\n');
  static void password(String p) {if(p.length<10 || p.length>200)throw const FormatException('Use a password of 10–200 characters. Keep it outside this phone.');}
  static Future<SecretKey> key(String p,List<int> salt) => Pbkdf2(macAlgorithm:Hmac.sha256(),iterations:310000,bits:256).deriveKey(secretKey:SecretKey(utf8.encode(p)),nonce:salt);
  static Future<Uint8List> encrypt(Obj state,String p) async {
    password(p);final data=utf8.encode(encodeBackup(state)), algorithm=AesGcm.with256bits();
    final salt=SecretKeyData.random(length:16).bytes, nonce=algorithm.newNonce();
    final header=BytesBuilder()..add(magic)..add(_int(310000))..add(salt)..add(nonce)..add(_int(data.length+16));
    final box=await algorithm.encrypt(data,secretKey:await key(p,salt),nonce:nonce,aad:header.toBytes());
    return (BytesBuilder()..add(header.toBytes())..add(box.cipherText)..add(box.mac.bytes)).toBytes();
  }
  static Uint8List _int(int n)=>(ByteData(4)..setUint32(0,n,Endian.big)).buffer.asUint8List();
  static Future<Obj> decode(List<int> data,String p) async {
    if(data.length>64*1024*1024+1024)throw const FormatException('Backup exceeds 64 MB.');
    final bytes=Uint8List.fromList(data);
    if(bytes.isNotEmpty && bytes.first==123)return decodeBackup(utf8.decode(bytes));
    password(p);
    final m=bytes.length>=magic.length && utf8.decode(bytes.take(magic.length).toList(),allowMalformed:true)==utf8.decode(magic)?magic:legacyMagic;
    final headerLength=m.length+4+16+12+4;
    if(bytes.length<headerLength+16 || utf8.decode(bytes.take(m.length).toList(),allowMalformed:true)!=utf8.decode(m))throw const FormatException('Unsupported or truncated backup.');
    final view=ByteData.sublistView(bytes);if(view.getUint32(m.length,Endian.big)!=310000 || view.getUint32(headerLength-4,Endian.big)!=bytes.length-headerLength)throw const FormatException('Invalid encrypted backup settings.');
    final salt=bytes.sublist(m.length+4,m.length+20), nonce=bytes.sublist(m.length+20,m.length+32);
    try {final plain=await AesGcm.with256bits().decrypt(SecretBox(bytes.sublist(headerLength,bytes.length-16),nonce:nonce,mac:Mac(bytes.sublist(bytes.length-16))),secretKey:await key(p,salt),aad:bytes.sublist(0,headerLength));return decodeBackup(utf8.decode(plain));}
    catch(_){throw const FormatException('Wrong password or damaged backup. No records changed.');}
  }
  static Future<String?> export(String name,List<int> bytes) => FilePicker.platform.saveFile(dialogTitle:'Save backup outside this app',fileName:name,bytes:Uint8List.fromList(bytes));
  static Future<List<File>> recoveryFiles() async {
    final folder=Directory('${(await getApplicationSupportDirectory()).path}/recovery');
    if(!await folder.exists())return [];
    return folder.listSync().whereType<File>().toList()..sort((a,b)=>b.path.compareTo(a.path));
  }
  static Future<void> recovery(Obj state,String p) async {
    final folder=Directory('${(await getApplicationSupportDirectory()).path}/recovery');await folder.create(recursive:true);
    final bytes=await encrypt(state,p), file=File('${folder.path}/${DateTime.now().millisecondsSinceEpoch}.businessbk');
    await file.writeAsBytes(bytes,flush:true);await decode(await file.readAsBytes(),p);
    final files=folder.listSync().whereType<File>().toList()..sort((a,b)=>b.path.compareTo(a.path));for(final old in files.skip(7)) {await old.delete();}
  }
}
