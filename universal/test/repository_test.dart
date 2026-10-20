import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';
import 'package:business_tracker/core/bundles.dart';
import 'package:business_tracker/core/legacy.dart';
import 'package:business_tracker/services/repository.dart';
import 'package:business_tracker/core/purchases.dart';
import 'package:business_tracker/core/stocktakes.dart';
import 'package:business_tracker/services/sync.dart';
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  setUp(()async{sqfliteFfiInit();databaseFactory=databaseFactoryFfi;folder=await Directory.systemTemp.createTemp('tracker-test-');await databaseFactory.setDatabasesPath(folder.path);FlutterSecureStorage.setMockInitialValues({});});
  tearDown(()async{await folder.delete(recursive:true);});
  test('same sale confirmation is durable and deduplicated across repository reopen',()async{
    var r=await Repository.open();final s=clone(r.state);s['products']=[{'id':'repo-product-001','name':'Drink','category':'','variant':'','sellingPrice':350,'purchaseCost':100,'minimum':0,'barcode':'','photo':null}];await r.save(s);
    await r.append(event(id:'repo-restock-001',type:'restock',quantity:4,productId:'repo-product-001',cost:400));
    final sale=event(id:'repo-sale-00001',type:'sale',quantity:2,productId:'repo-product-001',revenue:600,fee:50,payment:'card');
    final results=await Future.wait(List.generate(30,(_)=>r.recordSale(sale)));expect(results.every((v)=>v),true);expect(objects(r.state['events']).length,2);expect(objects(r.state['moneyEntries']),hasLength(1));expect(objects(r.state['moneyEntries']).single['delta'],550);
    await r.close();r=await Repository.open();expect(await r.recordSale(sale),false);expect(validateState(r.state).book.stock('repo-product-001'),2);expect(r.state['lastPayment'],'card');expect(validateState(r.state).summary()['revenue'],600);expect(objects(r.state['moneyEntries']),hasLength(1));expect(objects(r.state['moneyEntries']).single['delta'],550);
    await expectLater(r.recordSale({...sale,'revenue':700}),throwsFormatException);await r.close();
  });
  test('bundle sale is idempotent across confirmation and backup restore',()async{
    var r=await Repository.open();
    final state=clone(r.state);
    state['products']=[
      {'id':'bundle-prod-a-001','name':'A','category':'Skincare','variant':'','sellingPrice':900,'purchaseCost':null,'minimum':0,'barcode':'','photo':null},
      {'id':'bundle-prod-b-001','name':'B','category':'Skincare','variant':'','sellingPrice':900,'purchaseCost':null,'minimum':0,'barcode':'','photo':null},
    ];
    final bundle=<String,dynamic>{'id':'bundle-repo-001','name':'Two item set','category':'Skincare','description':'','sellingPrice':1500,'components':[{'productId':'bundle-prod-a-001','quantity':1},{'productId':'bundle-prod-b-001','quantity':1}],'archived':false,'photo':null};
    state['bundles']=[bundle];await r.save(state);
    await r.append(event(id:'bundle-repo-stock-a',type:'restock',quantity:2,productId:'bundle-prod-a-001',cost:400));
    await r.append(event(id:'bundle-repo-stock-b',type:'restock',quantity:2,productId:'bundle-prod-b-001',cost:600));
    final sale=bundleSaleEvent(id:'bundle-repo-sale-01',bundle:bundle,bundleQuantity:1,revenue:1500,payment:'card',note:'',date:DateTime.now().millisecondsSinceEpoch,recordedAt:DateTime.now().millisecondsSinceEpoch);
    expect(await r.recordSale(sale),isTrue);expect(await r.recordSale(sale),isFalse);
    expect(validateState(r.state).book.stock('bundle-prod-a-001'),1);expect(validateState(r.state).book.stock('bundle-prod-b-001'),1);
    final backup=decodeBackup(encodeBackup(r.state));await r.restore(backup);
    expect(objects(r.state['events']).where((e)=>e['bundleId']=='bundle-repo-001'),hasLength(1));
    await r.close();r=await Repository.open();
    expect(validateState(r.state).book.stock('bundle-prod-a-001'),1);expect(validateState(r.state).book.stock('bundle-prod-b-001'),1);
    expect(validateState(r.state).summary()['revenue'],1500);expect(validateState(r.state).summary()['cogs'],500);
    await r.close();
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
    final conflicting=objects(purchase).map(clone).toList();obj(conflicting.first['purchaseLine'])['cost']=4801;conflicting.first['cost']=4801;
    await expectLater(r.recordPurchase(conflicting),throwsFormatException);expect(validateState(r.state).book.stock('purchase-product-01'),52);
    await r.close();
  });
  test('stocktake confirmation is atomic, concurrent retries apply adjustments once, and history survives reopen',()async{
    var r=await Repository.open();final state=clone(r.state);
    state['products']=[{'id':'stocktake-product-01','name':'Drink','category':'Monster','variant':'500 ml','sellingPrice':350,'purchaseCost':100,'minimum':0,'barcode':'','photo':null}];await r.save(state);
    await r.append(event(id:'stocktake-restock-01',type:'restock',quantity:5,productId:'stocktake-product-01',cost:500));
    var draft=startStocktake(r.state,id:'stocktake-repo-session-01',at:1780000000000);
    draft=recordStocktakeCount(draft,'stocktake-repo-session-01','stocktake-product-01',sellable:3,damaged:1,eventCount:1,countedAt:1780000001000);await r.save(draft);
    final results=await Future.wait([r.confirmStocktakeSession('stocktake-repo-session-01'),r.confirmStocktakeSession('stocktake-repo-session-01')]);
    expect(results,[true,true]);expect(validateState(r.state).book.stock('stocktake-product-01'),3);
    expect(objects(r.state['events']).where((e)=>e['stocktakeSessionId']=='stocktake-repo-session-01'),hasLength(2));
    expect(await r.confirmStocktakeSession('stocktake-repo-session-01'),false);await r.close();
    r=await Repository.open();expect(stocktakeSessions(r.state).single['status'],'completed');expect(validateState(r.state).summary()['revenue'],0);await r.close();
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
