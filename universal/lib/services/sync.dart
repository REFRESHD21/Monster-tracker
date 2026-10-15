import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:workmanager/workmanager.dart';
import 'package:sqflite/sqflite.dart';
import '../core/codec.dart';
import 'repository.dart';
import 'backups.dart';
import 'google_sheets.dart';
import 'package:uuid/uuid.dart';
const secrets=FlutterSecureStorage(iOptions:IOSOptions(accessibility:KeychainAccessibility.first_unlock));
List<Obj> syncRecords(Obj state) {
  final out=<Obj>[];
  void add(String kind,String id,Obj body)=>out.add({'id':'$kind-$id','kind':kind,'body':body});
  for(final e in objects(state['events'])) {add('event',e['id'],e);}
  for(final p in objects(state['products'])) {final body={...p}..remove('photo');add('product','${p['id']}-${digest(p)}',body);}
  for(final a in objects(state['attachments'])) {final body={...a}..remove('data');add('receipt',a['id'],body);}
  final legacy=state['legacy'];
  if(legacy!=null) {
    final b=obj(legacy['business'] ?? {});
    for(final kind in ['documents','deliveries','cancellations','audit']) {for(final record in objects(b[kind] ?? [])) {add('legacy-$kind',record['id'],record);}}
    for(final r in objects(b['receipts'] ?? [])) {final body={...r}..remove('content');add('supplier-receipt',r['hash'],body);}
    for(final r in objects(b['catalog']?['barcodes'] ?? [])) {add('barcode',digest(r),r);}
    for(final kind in ['requests','observations','returns']) {for(final r in objects(b['refunds']?[kind] ?? [])) {add('legacy-refund-$kind',r['id'],r);}}
  }
  add('business',digest({'name':state['businessName']}),{'name':state['businessName'],'currency':'AUD','timeZone':'Australia/Perth'});
  return out;
}
class Sheets {
  static Future<void> configure(String url,String token,bool automatic)=>exclusive((_) async {
    final u=Uri.tryParse(url.trim());
    if(u==null || u.scheme!='https' || u.host!='script.google.com' || u.hasPort || u.userInfo.isNotEmpty || u.hasQuery || u.hasFragment || !RegExp(r'^/macros/s/[A-Za-z0-9_-]+/exec$').hasMatch(u.path) || token.length<32)throw const FormatException('Enter a deployed Apps Script /exec URL and a token of at least 32 characters.');
    await secrets.write(key:'sheets-mode',value:'script');await secrets.write(key:'sheets-url',value:url.trim());await secrets.write(key:'sheets-token',value:token);await secrets.write(key:'sheets-auto',value:'$automatic');
    for(final key in ['sheets-google-id','sheets-account','sheets-email','sheets-snapshot','sheets-last','sheets-error']){await secrets.delete(key:key);}
    await automaticUploads(automatic);
  });
  static Future<void> automaticUploads(bool enabled) async {
    await secrets.write(key:'sheets-auto',value:'$enabled');
    if(enabled){await Workmanager().registerPeriodicTask('au.monster.tracker.plus.sync','au.monster.tracker.plus.sync',frequency:const Duration(minutes:15),constraints:Constraints(networkType:NetworkType.connected));}
    else{await Workmanager().cancelByUniqueName('au.monster.tracker.plus.sync');}
  }
  static Future<void> initializeConnection()=>exclusive((_)async{});
  static Future<void> _identity(Repository repo) async {
    final local=(await repo.db.query('local_identity')).single;
    final previous=await secrets.read(key:'sheets-local-identity');
    if(previous==local['id'])return;
    // Keychain can survive an iOS uninstall. A new local database must not inherit
    // another installation's connection, while an in-place v3 upgrade retains it.
    if(previous!=null || local['migrated']==0){
      for(final key in ['sheets-mode','sheets-google-id','sheets-account','sheets-email','sheets-snapshot','sheets-url','sheets-token','sheets-auto','sheets-last','sheets-error']){await secrets.delete(key:key);}
    }else if(await secrets.read(key:'sheets-url')!=null){await secrets.write(key:'sheets-mode',value:'script');}
    await secrets.write(key:'sheets-local-identity',value:local['id'] as String);
  }
  static Future<T> exclusive<T>(Future<T> Function(Repository) fn) async {
    final repo=await Repository.open(migrate:false),owner=const Uuid().v4();
    var acquired=false;Timer? heartbeat;
    try {
      acquired=await repo.db.transaction((txn) async {
        final now=DateTime.now().millisecondsSinceEpoch;
        await txn.delete('task_lock',where:'expires<?',whereArgs:[now]);
        if((await txn.query('task_lock',where:'name=?',whereArgs:['sheets'])).isNotEmpty)return false;
        await txn.insert('task_lock',{'name':'sheets','owner':owner,'expires':now+300000});return true;
      });
      if(!acquired)throw const FormatException('An upload or connection change is already in progress. Retry shortly; an interrupted job releases within five minutes.');
      heartbeat=Timer.periodic(const Duration(minutes:1),(_)async{try{await repo.db.update('task_lock',{'expires':DateTime.now().millisecondsSinceEpoch+300000},where:'name=? AND owner=?',whereArgs:['sheets',owner]);}catch(_){/* Upload outcome remains pending if the worker stops. */}});
      await _identity(repo);
      return await fn(repo);
    }finally{
      heartbeat?.cancel();
      if(acquired)await repo.db.delete('task_lock',where:'name=? AND owner=?',whereArgs:['sheets',owner]);
      await repo.close();
    }
  }
  static Future<void> disconnect() async {
    await automaticUploads(false);
    await exclusive((_)=>GoogleSheets.disconnect());
  }
  static Future<void> upload(Obj state,{bool force=false})=>exclusive((repo) async {
    // Re-read under the lock: a scheduled task may have captured an older revision.
    try {
      if(await secrets.read(key:'sheets-mode')=='google'){await GoogleSheets.upload(repo.state,force:force);}
      else{await _scriptUpload(repo.state,force:force);}
    }catch(e){await secrets.write(key:'sheets-error',value:'$e');rethrow;}
  });
  static Future<void> _scriptUpload(Obj state,{bool force=false}) async {

    final url=await secrets.read(key:'sheets-url'), token=await secrets.read(key:'sheets-token');
    if(url==null || token==null)throw const FormatException('Configure Google Sheets first.');
    final repo=await Repository.open(migrate:false);
    final acknowledged=await repo.db.query('sync_ack',where:'destination=? AND business_id=?',whereArgs:[url,state['businessId']]);
    final hashes={for(final a in acknowledged) a['record_id']:a['hash']};
    final records=syncRecords(state).where((r)=>force || hashes[r['id']]!=digest(r)).toList(), client=HttpClient()..connectionTimeout=const Duration(seconds:20);
    try {
      for(var i=0;i<records.length;i+=50) {
        final batch=records.skip(i).take(50).toList();final request=await client.postUrl(Uri.parse(url));request.followRedirects=false;request.headers.contentType=ContentType.json;
        request.write(jsonEncode({'token':token,'businessId':state['businessId'],'records':batch}));var response=await request.close().timeout(const Duration(seconds:30));
        if(response.statusCode==302 || response.statusCode==303) {final redirect=Uri.parse(response.headers.value('location') ?? '');if(redirect.scheme!='https' || redirect.host!='script.googleusercontent.com' || redirect.userInfo.isNotEmpty)throw const FormatException('Unexpected Sheets redirect.');await response.drain<void>();final get=await client.getUrl(redirect);get.followRedirects=false;response=await get.close().timeout(const Duration(seconds:30));}
        if(response.statusCode!=200)throw const FormatException('Sheets endpoint unavailable.');
        final text=await utf8.decoder.bind(response).join().timeout(const Duration(seconds:30));if(text.length>16384)throw const FormatException('Invalid Sheets response.');
        final reply=obj(jsonDecode(text));if(reply['ok']!=true || reply['accepted']!=batch.length)throw const FormatException('Upload rejected. Update the receiver and check its token.');
        await repo.db.transaction((txn) async {for(final record in batch){await txn.insert('sync_ack',{'destination':url,'business_id':state['businessId'],'record_id':record['id'],'hash':digest(record)},conflictAlgorithm:ConflictAlgorithm.replace);}});
      }
      await secrets.write(key:'sheets-last',value:DateTime.now().toIso8601String());await secrets.write(key:'sheets-error',value:'');
    } catch(e) {await secrets.write(key:'sheets-error',value:'Upload incomplete. Records remain on this phone. Retry when connected.');rethrow;} finally {client.close(force:true);await repo.close();}
  }
}
@pragma('vm:entry-point')
void backgroundTasks() {
  DartPluginRegistrant.ensureInitialized();
  Workmanager().executeTask((task,input) async {
    Repository? r;
    try {r=await Repository.open(migrate:false);
      if(task=='au.monster.tracker.plus.backup') {final p=await secrets.read(key:'backup-password');if(p!=null) {final every=await secrets.read(key:'backup-frequency'),last=int.tryParse(await secrets.read(key:'backup-last') ?? '0') ?? 0;if(DateTime.now().millisecondsSinceEpoch-last>(every=='weekly'?7:1)*86400000){await Backups.recovery(r.state,p);await secrets.write(key:'backup-last',value:'${DateTime.now().millisecondsSinceEpoch}');}}}
      else if(await secrets.read(key:'sheets-auto')=='true') {await Sheets.upload(r.state);}
      return true;
    } catch(_) {return false;} finally {await r?.close();}
  });
}
