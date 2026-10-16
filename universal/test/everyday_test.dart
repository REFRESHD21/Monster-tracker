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
  test('partial tab creation and failed writes leave acknowledgement pending',()async{
    final snapshot=sheetSnapshot(emptyState()),tabs=<int,Obj>{};String? ack;var failCreate=true,failWrite=true;
    Future<void> send(List<Obj> requests)async{
      for(final r in requests){if(r['addSheet']!=null){final p=obj(r['addSheet']['properties']);tabs[p['sheetId']]=p;if(failCreate){failCreate=false;throw TimeoutException('Lost creation response');}}}
      if(requests.first.containsKey('updateCells') && failWrite){failWrite=false;throw TimeoutException('Offline before acknowledgement');}
    }
    Future<void> run()=>uploadSnapshot(snapshot:snapshot,installation:'installation-test',metadata:()async=>{'sheets':[for(final p in tabs.values){'properties':p}]},send:send,acknowledge:(h)async{ack=h;});
    await expectLater(run(),throwsA(isA<TimeoutException>()));expect(tabs.length,1);expect(ack,isNull);
    await expectLater(run(),throwsA(isA<TimeoutException>()));expect(tabs.length,snapshot.length);expect(ack,isNull);
    await run();expect(ack,digest(snapshot));expect(tabs.length,snapshot.length);
  });
  test('existing unrelated tab ID collision is rejected before any write',()async{
    final snapshot=sheetSnapshot(emptyState());var wrote=false;
    await expectLater(uploadSnapshot(snapshot:snapshot,installation:'installation-test',metadata:()async=>{'sheets':[{'properties':{'sheetId':sheetNumber('Products','installation-test'),'title':'Someone elses tab','gridProperties':{'rowCount':1000}}}]},send:(_)async{wrote=true;},acknowledge:(_)async{}),throwsFormatException);
    expect(wrote,false);
  });

}
