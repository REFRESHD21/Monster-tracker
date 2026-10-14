import 'dart:convert';
import 'codec.dart';
import 'engine.dart';

Obj importLegacy(String text) {
  final root=obj(strictJson(text)), version=integer(root['version'],1,6);
  if(root['format']!='monster-tracker-offline' || root['currency']!='AUD' || root['timeZone']!='Australia/Perth') throw const FormatException('Unsupported legacy backup.');
  final unsigned={...root}..remove('sha256');
  if(digest(unsigned)!=root['sha256']) throw const FormatException('Backup checksum failed. Nothing imported.');
  final source=objects(root['events']); if(source.length<2 || source.length>10000) throw const FormatException('Invalid legacy history.');
  final opening=[{'id':'opening-purchase-v1','type':'restock','quantity':24,'cost':5000,'note':'Opening purchase; date unknown'}, {'id':'opening-missing-v1','type':'missing','quantity':4,'cost':0,'note':'Imported from existing Log row 2; date unknown'}];
  for(var i=0;i<2;i++) { final e=source[i];for(final k in opening[i].keys) {if(e[k]!=opening[i][k]) throw const FormatException('Opening records were changed.');}if(e['timestamp']!=null || e['payment']!='none' || e['revenue']!=0 || e['fee']!=0 || e['target']!=null) throw const FormatException('Invalid opening history.'); }
  final state=emptyState();state['businessName']='Monster business';state['legacy']=root;
  final business=version>=3 ? obj(root['business']) : <String,dynamic>{};
  final catalog=business['catalog']==null ? <String,dynamic>{} : obj(business['catalog']);
  final rawProducts=objects(catalog['products'] ?? []);
  final products=<Obj>[];
  for(final p in rawProducts) {products.add({'id':p['id'],'name':p['name'],'category':'','variant':'','purchaseCost':(p['packCost'] as int)~/(p['packSize'] as int),'sellingPrice':obj(root['prices'])['single'],'minimum':p['minimum'],'barcode':'','photo':null});}
  if(!products.any((p)=>p['id']==legacyProduct)) products.insert(0,{'id':legacyProduct,'name':'Unassigned historical stock','category':'','variant':'','purchaseCost':0,'sellingPrice':obj(root['prices'])['single'],'minimum':0,'barcode':'','photo':null});
  for(final b in objects(catalog['barcodes'] ?? [])) { final p=products.where((p)=>p['id']==b['productId']);if(p.isEmpty) throw const FormatException('Unknown barcode product.');if(p.first['barcode']=='')p.first['barcode']=b['code']; }
  state['products']=products;
  final allocations=<String,List<Obj>>{};
  for(final a in objects(catalog['allocations'] ?? [])) {if(allocations.containsKey(a['eventId'])) throw const FormatException('Duplicate allocation.');allocations[a['eventId'] as String]=objects(a['allocations']);}
  final taxes=<String,Obj>{};
  for(final t in objects(business['finance']?['taxes'] ?? [])) {final tax=obj(t['tax']);if(taxes.containsKey(t['id']) || tax['inputGst']>tax['actualGst'] || tax['registered']==false && (tax['inputGst']!=0 || tax['outputGst']!=0)) throw const FormatException('Invalid legacy GST.');taxes[t['id'] as String]=tax;}
  final refundData=obj(business['refunds'] ?? {'requests':[],'observations':[],'returns':[]});
  final requests={for(final r in objects(refundData['requests'])) r['id'] as String:r};
  final returnSources=<String,String>{};
  for(final r in objects(refundData['returns'])) {final request=requests[r['requestId']];if(request==null) throw const FormatException('Missing refund request.');returnSources[r['eventId'] as String]=request['saleId'] as String;}
  final reserved=<String,int>{},latest=<String,Obj>{};
  for(final o in objects(refundData['observations'])) {latest[o['requestId'] as String]=o;}
  for(final r in requests.values) {final status=latest[r['id']]?['status'];if(status==null || ['pending','requires_action'].contains(status))reserved[r['saleId'] as String]=(reserved[r['saleId']] ?? 0)+(r['amount'] as int);}
  final events=<Obj>[];
  final transfers=objects(catalog['transfers'] ?? []);
  final positions={for(var i=0;i<source.length;i++) source[i]['id'] as String:i};
  int anchor(Obj t) {
    if(t['afterEventId']!=null) {final p=positions[t['afterEventId']];if(p==null) throw const FormatException('Missing transfer anchor.');return p+1<2?2:p+1;}
    for(var i=2;i<source.length;i++) {if((t['recordedAt'] as int)<time(source[i]['recordedAt'])!)return i;}return source.length;
  }
  transfers.sort((a,b){final c=anchor(a).compareTo(anchor(b));return c==0?(a['recordedAt'] as int).compareTo(b['recordedAt'] as int):c;});
  var next=0;
  void move(Obj t) {events.add({...event(id:t['id'],type:'transfer',quantity:t['quantity'],note:t['note'],date:t['recordedAt']),'recordedAt':t['recordedAt'],'from':t['from'],'to':t['to']});}
  for(var i=0;i<source.length;i++) {
    while(i>=2 && next<transfers.length && anchor(transfers[next])<=i) {move(transfers[next++]);}
    final e=source[i], type=e['type'];
    if(type=='single' && e['quantity']!=1 || type=='deal' && e['quantity']!=2 || i>=2 && e['timestamp']==null) throw const FormatException('Invalid legacy sale/date.');
    final tax=taxes[e['id']] ?? {'inputGst':0,'outputGst':0};
    events.add({'id':e['id'],'type':returnSources.containsKey(e['id'])?'return':type,'date':time(e['timestamp']),'recordedAt':time(e['recordedAt']),'quantity':e['quantity'],'payment':e['payment'],'revenue':e['revenue'],'fee':e['fee'],'cost':e['cost'],'note':e['note'],'target':returnSources[e['id']] ?? e['target'],'inputGst':tax['inputGst'],'outputGst':tax['outputGst'],if((reserved[e['id']] ?? 0)>0)'reservedRefund':reserved[e['id']],'allocations':type=='undo'?[]:allocations[e['id']] ?? [{'productId':legacyProduct,'quantity':e['quantity']}]});
  }
  while(next<transfers.length) {move(transfers[next++]);}
  final docs=objects(business['documents'] ?? []);
  for(final d in docs) {
    int gross=0,gst=0;
    if(d['kind']=='expense') {gross=d['amount'];gst=d['gst'];} else {int total=0,totalGst=0;for(final l in objects(d['lines'])) {total+=integer(l['cost']);totalGst+=integer(l['gst']);if(l['stock']==false){gross+=l['cost'] as int;gst+=l['gst'] as int;}}if(total!=d['amount'] || totalGst!=d['gst']) throw const FormatException('Purchase totals do not match.');}
    if(gross==0)continue;
    final input=taxes[d['id']]?['inputGst'] ?? 0;if(input>gst) throw const FormatException('Expense GST exceeds receipt.');
    events.add({...event(id:d['id'],type:'expense',cost:gross,inputGst:input,note:'${d['category']} · ${d['note']}'),'date':d['date'],'recordedAt':d['recordedAt']});
  }
  for(final c in objects(business['cancellations'] ?? [])) {if(events.any((e)=>e['id']==c['documentId'] && e['type']=='expense'))events.add({...event(id:c['id'],type:'undo',target:c['documentId'],note:c['note'],date:c['recordedAt']),'recordedAt':c['recordedAt']});}
  final previous=<String,Obj>{};
  for(final o in objects(refundData['observations'])) {
    final r=requests[o['requestId']];if(r==null)throw const FormatException('Missing refund request.');
    final prior=previous[o['requestId']];previous[o['requestId'] as String]=o;
    final delta=(o['status']=='succeeded'?r['amount'] as int:0)-(prior?['status']=='succeeded'?r['amount'] as int:0);
    final fee=(o['fee'] as int? ?? 0)-(prior?['fee'] as int? ?? 0);
    events.add({...event(id:o['id'],type:'refund_observation',target:r['saleId'],note:r['note']),'date':o['created'],'recordedAt':o['verifiedAt'],'delta':delta,'feeDelta':fee});
  }
  final attachments=<Obj>[];
  for(final a in objects(root['receipts'] ?? [])) {attachments.add({'id':a['id'],'eventId':a['eventId'],'mime':a['mime'],'data':a['base64'],'sha256':a['sha256']});}
  // Original supplier PDFs/photos and their exact associations stay inside legacy.
  for(final a in objects(business['receipts'] ?? [])) {final bytes=base64Decode(a['content']);if(bytesHash(bytes)!=a['hash'] || bytes.isEmpty || bytes.length>16*1024*1024) throw const FormatException('Damaged supplier receipt.');}
  state['events']=events;state['attachments']=attachments;state['legacyCount']=events.length;
  validateState(state);return state;
}
Obj decodeBackup(String text) {
  final root=obj(strictJson(text));
  if(root['format']=='monster-tracker-offline')return importLegacy(text);
  if(root['format']!='business-tracker-backup' || root['version']!=1)throw const FormatException('Unsupported backup format.');
  final unsigned={...root}..remove('sha256');if(root['sha256']!=digest(unsigned))throw const FormatException('Backup checksum failed.');
  final s=obj(root['state']); validateState(s);
  if(s['legacy']!=null) {final imported=importLegacy(canonical(s['legacy']));final count=integer(s['legacyCount'],0,100100);if(count!=objects(imported['events']).length || canonical(objects(s['events']).take(count).toList())!=canonical(imported['events'])) throw const FormatException('Historical migration records changed.');}
  return s;
}
String encodeBackup(Obj state) {validateState(state);final root=<String,dynamic>{'format':'business-tracker-backup','version':1,'state':state};root['sha256']=digest(root);return canonical(root);}
Obj mergeBackup(Obj current, Obj incoming) {
  validateState(current);validateState(incoming);
  if(objects(current['events']).isEmpty && objects(current['products']).isEmpty)return clone(incoming);
  if(canonical(current)==canonical(incoming))return clone(current);
  final old=objects(current['events']), next=objects(incoming['events']);
  if(current['businessId']==incoming['businessId'] && canonical(next.take(old.length).toList())==canonical(old) && canonical(current['legacy'])==canonical(incoming['legacy'])) {
    final restored=clone(incoming), receiptIds={for(final a in objects(restored['attachments'])) a['id']:a};
    for(final a in objects(current['attachments'])) {if(receiptIds.containsKey(a['id']) && canonical(receiptIds[a['id']])!=canonical(a))throw const FormatException('Conflicting receipt.');if(!receiptIds.containsKey(a['id']))(restored['attachments'] as List).add(a);}
    for(final p in objects(current['products'])) {if(!objects(restored['products']).any((n)=>n['id']==p['id']))(restored['products'] as List).add(p);}
    validateState(restored);return restored;
  }
  if(current['businessId']!=incoming['businessId'] || canonical(old.take(next.length).toList())!=canonical(next) || canonical(current['legacy'])!=canonical(incoming['legacy'])) throw const FormatException('Different or conflicting history. Restore into an empty installation; current records were not changed.');
  // A previously imported backup must never roll back later records or product settings.
  return clone(current);
}
