import 'codec.dart';

/// A report mirror. Sheets values are never imported into the app.
Map<String,List<List<dynamic>>> sheetSnapshot(Obj state) {
  final products=objects(state['products']),events=objects(state['events']);
  List<List<dynamic>> rows(List<String> keys,Iterable<Obj> items)=>[keys,for(final r in items)[for(final k in keys)r[k] is List || r[k] is Map?canonical(r[k]):r[k] ?? '']];
  final eventKeys=['id','type','date','quantity','revenue','cost','fee','payment','allocations','target','note','inputGst','outputGst'];
  return {
    'Products':rows(['id','name','category','variant','sellingPrice','twoItemPrice','archived','purchaseCost','minimum','barcode'],products),
    'Sales':rows(eventKeys,events.where((e)=>['single','deal','sale','refund','refund_observation','return','undo'].contains(e['type']))),
    'Purchases':rows([...eventKeys,'purchaseBatch','purchaseLine'],events.where((e)=>['opening','restock','transfer','missing','damaged','undo'].contains(e['type']))),
    'Expenses':rows(eventKeys,events.where((e)=>['expense','undo'].contains(e['type']))),
    'OriginalDocuments':rows(['id','kind','supplier','reference','date','amount','gst','lines','note'],objects(state['legacy']?['business']?['documents'] ?? [])),
  };
}
String sheetTitle(String name,String installation)=>'${name}_$installation';
int sheetNumber(String name,String installation)=>int.parse(digest('$name:$installation').substring(0,7),radix:16)+1;
Obj snapshotWrite(String name,String installation,List rows)=>{'updateCells':{
  'range':{'sheetId':sheetNumber(name,installation),'startRowIndex':0,'startColumnIndex':0},
  'rows':[for(final row in rows){'values':[for(final value in row as List){'userEnteredValue':value is int?{'numberValue':value}:value is bool?{'boolValue':value}:{'stringValue':'$value'}}]}],
  'fields':'userEnteredValue',
}};
