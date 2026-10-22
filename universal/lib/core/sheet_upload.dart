import 'codec.dart';
import 'sheet_snapshot.dart';

/// Transport/ack boundary is injectable so a lost response can be tested.
Future<void> uploadSnapshot({required Map<String,List<List<dynamic>>> snapshot,required String installation,required Future<Obj> Function() metadata,required Future<void> Function(List<Obj>) send,required Future<void> Function(String) acknowledge}) async {
  final properties=objects((await metadata())['sheets'] ?? []).map((s)=>obj(s['properties'])).toList();
  final add=<Obj>[];
  for(final name in snapshot.keys){
    final title=sheetTitle(name,installation),sheetId=sheetNumber(name,installation);
    final existing=properties.where((p)=>p['sheetId']==sheetId || p['title']==title).firstOrNull;
    if(existing!=null && (existing['sheetId']!=sheetId || existing['title']!=title))throw const FormatException('An existing tab conflicts with this installation. Choose a different spreadsheet.');
    final rows=snapshot[name]!.length;
    if(rows>100001)throw const FormatException('Upload exceeds supported tab size. Export CSV instead.');
    if(existing==null){add.add({'addSheet':{'properties':{'sheetId':sheetId,'title':title,'gridProperties':{'rowCount':rows<1000?1000:rows,'columnCount':16}}}});}
    else if((existing['gridProperties']['rowCount'] as int)<rows){add.add({'updateSheetProperties':{'properties':{'sheetId':sheetId,'gridProperties':{'rowCount':rows}},'fields':'gridProperties.rowCount'}});}
  }
  if(add.isNotEmpty)await send(add);
  // Whole app-owned tab ranges clear obsolete trailing cells. RAW typed values
  // make user text such as =IMPORTXML(...) a string, never a formula.
  await send(snapshot.entries.map((entry)=>snapshotWrite(entry.key,installation,entry.value)).toList());
  await acknowledge(digest(snapshot));
}
