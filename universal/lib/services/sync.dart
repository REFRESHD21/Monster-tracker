import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:workmanager/workmanager.dart';
import '../core/codec.dart';
import 'repository.dart';
import 'backups.dart';
const secrets=FlutterSecureStorage();
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
  static Future<void> configure(String url,String token,bool automatic) async {
    final u=Uri.tryParse(url.trim());
    if(u==null || u.scheme!='https' || u.host!='script.google.com' || u.hasPort || u.userInfo.isNotEmpty || u.hasQuery || u.hasFragment || !RegExp(r'^/macros/s/[A-Za-z0-9_-]+/exec$').hasMatch(u.path) || token.length<32)throw const FormatException('Enter a deployed Apps Script /exec URL and a token of at least 32 characters.');
    await secrets.write(key:'sheets-url',value:url.trim());await secrets.write(key:'sheets-token',value:token);await secrets.write(key:'sheets-auto',value:'$automatic');
    if(automatic) {await Workmanager().registerPeriodicTask('tracker-sync','tracker-sync',frequency:const Duration(minutes:15),constraints:Constraints(networkType:NetworkType.connected));}
    else {await Workmanager().cancelByUniqueName('tracker-sync');}
  }
  static Future<void> upload(Obj state) async {
    final url=await secrets.read(key:'sheets-url'), token=await secrets.read(key:'sheets-token');
    if(url==null || token==null)throw const FormatException('Configure Google Sheets first.');
    final records=syncRecords(state), client=HttpClient()..connectionTimeout=const Duration(seconds:20);
    try {
      for(var i=0;i<records.length;i+=50) {
        final batch=records.skip(i).take(50).toList();final request=await client.postUrl(Uri.parse(url));request.followRedirects=false;request.headers.contentType=ContentType.json;
        request.write(jsonEncode({'token':token,'businessId':state['businessId'],'records':batch}));var response=await request.close().timeout(const Duration(seconds:30));
        if(response.statusCode==302 || response.statusCode==303) {final redirect=Uri.parse(response.headers.value('location') ?? '');if(redirect.scheme!='https' || redirect.host!='script.googleusercontent.com' || redirect.userInfo.isNotEmpty)throw const FormatException('Unexpected Sheets redirect.');await response.drain<void>();final get=await client.getUrl(redirect);get.followRedirects=false;response=await get.close().timeout(const Duration(seconds:30));}
        if(response.statusCode!=200)throw const FormatException('Sheets endpoint unavailable.');
        final text=await utf8.decoder.bind(response).join().timeout(const Duration(seconds:30));if(text.length>16384)throw const FormatException('Invalid Sheets response.');
        final reply=obj(jsonDecode(text));if(reply['ok']!=true || reply['accepted']!=batch.length)throw const FormatException('Upload rejected. Update the receiver and check its token.');
      }
      await secrets.write(key:'sheets-last',value:DateTime.now().toIso8601String());await secrets.write(key:'sheets-error',value:'');
    } catch(e) {await secrets.write(key:'sheets-error',value:'Upload incomplete. Records remain on this phone. Retry when connected.');rethrow;} finally {client.close(force:true);}
  }
}
@pragma('vm:entry-point')
void backgroundTasks() {
  Workmanager().executeTask((task,input) async {
    Repository? r;
    try {r=await Repository.open(migrate:false);
      if(task=='tracker-backup') {final p=await secrets.read(key:'backup-password');if(p!=null)await Backups.recovery(r.state,p);}
      else if(await secrets.read(key:'sheets-auto')=='true') {await Sheets.upload(r.state);}
      return true;
    } catch(_) {return false;} finally {await r?.close();}
  });
}
