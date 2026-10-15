import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';
import 'package:business_tracker/services/repository.dart';
import 'package:business_tracker/services/sync.dart';
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  setUp(()async{sqfliteFfiInit();databaseFactory=databaseFactoryFfi;folder=await Directory.systemTemp.createTemp('tracker-test-');await setDatabasesPath(folder.path);FlutterSecureStorage.setMockInitialValues({});});
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
    final other=await Directory('${folder.path}/second-install').create();await setDatabasesPath(other.path);final second=await Repository.open();await second.restore(backup);final id=(await second.db.query('local_identity')).single['id'];expect(id,isNot(first));expect(second.state['businessId'],backup['businessId']);await Sheets.initializeConnection();expect(await secrets.read(key:'sheets-local-identity'),id);await second.close();
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
}
