import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';
import 'package:business_tracker/services/repository.dart';
import 'package:business_tracker/core/purchases.dart';
import 'package:business_tracker/services/sync.dart';
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  setUp(()async{sqfliteFfiInit();databaseFactory=databaseFactoryFfi;folder=await Directory.systemTemp.createTemp('tracker-test-');await databaseFactory.setDatabasesPath(folder.path);FlutterSecureStorage.setMockInitialValues({});});
  tearDown(()async{await folder.delete(recursive:true);});
  test('same sale confirmation is durable and deduplicated across repository reopen',()async{
    var r=await Repository.open();final s=clone(r.state);s['products']=[{'id':'repo-product-001','name':'Drink','category':'','variant':'','sellingPrice':350,'purchaseCost':100,'minimum':0,'barcode':'','photo':null}];await r.save(s);
    await r.append(event(id:'repo-restock-001',type:'restock',quantity:4,productId:'repo-product-001',cost:400));
    final sale=event(id:'repo-sale-00001',type:'sale',quantity:2,productId:'repo-product-001',revenue:600,payment:'card');
    final results=await Future.wait(List.generate(30,(_)=>r.recordSale(sale)));expect(results.every((v)=>v),true);expect(objects(r.state['events']).length,2);
    await r.close();r=await Repository.open();expect(await r.recordSale(sale),false);expect(validateState(r.state).book.stock('repo-product-001'),2);expect(r.state['lastPayment'],'card');expect(validateState(r.state).summary()['revenue'],600);
    await expectLater(r.recordSale({...sale,'revenue':700}),throwsFormatException);await r.close();
  });
  test('fresh database clears surviving keychain connection; restore has independent identity',()async{
    FlutterSecureStorage.setMockInitialValues({'sheets-google-id':'old-sheet','sheets-account':'old-account','sheets-mode':'google','sheets-auto':'true','sheets-local-identity':'previous-install'});
    final r=await Repository.open();final first=(await r.db.query('local_identity')).single['id'];await Sheets.initializeConnection();expect(await secrets.read(key:'sheets-google-id'),null);expect(await secrets.read(key:'sheets-auto'),null);final backup=clone(r.state);await r.close();
    final other=await Directory('${folder.path}/second-install').create();await databaseFactory.setDatabasesPath(other.path);final second=await Repository.open();await second.restore(backup);final id=(await second.db.query('local_identity')).single['id'];expect(id,isNot(first));expect(second.state['businessId'],backup['businessId']);await Sheets.initializeConnection();expect(await secrets.read(key:'sheets-local-identity'),id);await second.close();
  });
  test('v3 in-place schema upgrade retains advanced connection and history',()async{
    final r=await Repository.open();final before=canonical(r.state);
    await r.db.execute('DROP TABLE task_lock');await r.db.execute('DROP TABLE local_identity');await r.db.execute('PRAGMA user_version=3');await r.close();
    FlutterSecureStorage.setMockInitialValues({'sheets-url':'https://script.google.com/macros/s/test/exec','sheets-token':'old-pairing-token','sheets-auto':'true'});
    final updated=await Repository.open();expect(canonical(updated.state),before);expect((await updated.db.query('local_identity')).single['migrated'],1);await Sheets.initializeConnection();expect(await secrets.read(key:'sheets-token'),'old-pairing-token');expect(await secrets.read(key:'sheets-mode'),'script');await updated.close();
    final db=await openDatabase(path.join(folder.path,'business-tracker-v1.db'));expect(await db.getVersion(),4);await db.close();
  });
  test('database upload lease excludes concurrent workers and recovers an expired lease',()async{
    final r=await Repository.open();await r.close();final entered=Completer<void>(),release=Completer<void>();
    final first=Sheets.exclusive((_)async{entered.complete();await release.future;});await entered.future;
    await expectLater(Sheets.exclusive((_)async{}),throwsFormatException);release.complete();await first;
    final reopened=await Repository.open();await reopened.db.insert('task_lock',{'name':'sheets','owner':'dead-worker','expires':0});await reopened.close();
    var ran=false;await Sheets.exclusive((_)async{ran=true;});expect(ran,true);
  });
  test('sale waits out a real SQLite writer lock and commits once',()async{
    final r=await Repository.open();
    final state=clone(r.state);state['products']=[{'id':'locked-product-001','name':'Drink','category':'','variant':'','sellingPrice':350,'purchaseCost':100,'minimum':0,'barcode':'','photo':null}];await r.save(state);
    await r.append(event(id:'locked-restock-001',type:'restock',quantity:4,productId:'locked-product-001',cost:400));
    await r.db.execute('PRAGMA busy_timeout=0');
    final blocker=await openDatabase(path.join(folder.path,'business-tracker-v1.db'),singleInstance:false);
    await blocker.execute('BEGIN IMMEDIATE');
    final sale=event(id:'locked-sale-00001',type:'sale',quantity:2,productId:'locked-product-001',revenue:600,payment:'card');
    final outcome=r.recordSale(sale).then<Object>((value)=>value,onError:(Object error)=>error);
    await Future<void>.delayed(const Duration(milliseconds:100));
    await blocker.execute('COMMIT');await blocker.close();
    expect(await outcome,true);expect(await r.recordSale(sale),false);
    expect(objects(r.state['events']).where((e)=>e['id']==sale['id']).length,1);
    expect(validateState(r.state).book.stock('locked-product-001'),2);expect(r.state['lastPayment'],'card');
    await r.close();
  });

  test('purchase batches commit atomically and retries do not add stock twice',()async{
    final r=await Repository.open();final state=clone(r.state);
    state['products']=[{'id':'purchase-product-01','name':'Drink','category':'Monster','variant':'500 ml','sellingPrice':350,'purchaseCost':100,'minimum':0,'barcode':'','photo':null}];await r.save(state);
    var n=0;final purchase=createPurchaseEvents(purchaseId:'purchase-batch-0001',supplier:'Costco',location:'Perth',reference:'receipt-7',note:'',date:1780000000000,newEventId:()=> 'purchase-event-id-${n++}',lines:[{'lineId':'purchase-line-id-001','productId':'purchase-product-01','packSize':24,'packCount':2,'cost':4800},{'lineId':'purchase-line-id-002','productId':'purchase-product-01','packSize':4,'packCount':1,'cost':1000}]);
    final result=await Future.wait([r.recordPurchase(purchase),r.recordPurchase(purchase)]);
    expect(result.every((saved)=>saved),true);expect(objects(r.state['events']).length,2);expect(validateState(r.state).book.stock('purchase-product-01'),52);
    expect(await r.recordPurchase(purchase),false);expect(validateState(r.state).book.stock('purchase-product-01'),52);
    final conflicting=clone(purchase);obj(conflicting.first['purchaseLine'])['cost']=4801;conflicting.first['cost']=4801;
    await expectLater(r.recordPurchase(conflicting),throwsFormatException);expect(validateState(r.state).book.stock('purchase-product-01'),52);
    await r.close();
  });
  test('stale repository still cannot overwrite a newer revision',()async{
    final first=await Repository.open(),stale=await Repository.open();
    final next=clone(first.state);next['businessName']='Newest records';await first.save(next);
    final old=clone(stale.state);old['businessName']='Stale records';
    await expectLater(stale.save(old),throwsStateError);
    await first.close();await stale.close();
    final reopened=await Repository.open();expect(reopened.state['businessName'],'Newest records');await reopened.close();
  });

}
