import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';
import 'package:business_tracker/core/sheet_snapshot.dart';
import 'package:business_tracker/core/sheet_upload.dart';
void main(){
  test('lost server response retries identical fixed rows; no acknowledgement until complete',()async{
    final snapshot=sheetSnapshot(emptyState()),tabs=<int,Obj>{},cells=<int,List>{};String? ack;var loseResponse=true;
    Future<void> send(List<Obj> requests)async{
      for(final r in requests){
        if(r['addSheet']!=null){final p=obj(r['addSheet']['properties']);tabs[p['sheetId']]=p;}
        if(r['updateCells']!=null){final u=obj(r['updateCells']);cells[u['range']['sheetId']]=u['rows'];}
      }
      if(requests.first.containsKey('updateCells') && loseResponse){loseResponse=false;throw TimeoutException('Response lost after Google committed');}
    }
    Future<void> run()=>uploadSnapshot(snapshot:snapshot,installation:'installation-a',metadata:()async=>{'sheets':[for(final p in tabs.values){'properties':p}]},send:send,acknowledge:(hash)async{ack=hash;});
    await expectLater(run(),throwsA(isA<TimeoutException>()));expect(ack,isNull);final before=canonical({'cells':cells.map((k,v)=>MapEntry('$k',v))});
    await run();expect(ack,digest(snapshot));expect(canonical({'cells':cells.map((k,v)=>MapEntry('$k',v))}),before);expect(tabs.length,snapshot.length);
    expect(sheetNumber('Sales','installation-a'),isNot(sheetNumber('Sales','installation-b')));
    final write=snapshotWrite('Products','installation-a',[['=IMPORTXML("bad")']]);expect(write['updateCells']['rows'][0]['values'][0]['userEnteredValue'],{'stringValue':'=IMPORTXML("bad")'});
  });
}
