import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:business_tracker/main.dart';
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';
import 'package:business_tracker/core/products.dart';
import 'package:business_tracker/services/repository.dart';
import 'package:business_tracker/services/google_sheets.dart';
import 'package:business_tracker/services/backups.dart';
import '../test_support/product_flow.dart';
void main(){
  final binding=IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('upgrade retains records and new universal saves survive restart', (tester) async {
    expect(GoogleSheets.configured,true,reason:'Android build must include the public Google OAuth client ID.');
    final repo=await Repository.open();
    final legacy=switch(const String.fromEnvironment('EXPECT_LEGACY',defaultValue:'true')){'true'=>true,_=>false};
    if(legacy){expect(repo.state['legacy'],isNotNull);expect(objects(repo.state['events']).length,4);expect(validateState(repo.state).book.stock(legacyProduct),25);expect(objects(repo.state['events'])[0]['date'],null);expect(objects(repo.state['events'])[2]['id'],'upgrade-restock-001');expect(objects(repo.state['events'])[3]['revenue'],777);final original=await openReadOnlyDatabase(path.join(await getDatabasesPath(),'monster-offline.db'));expect(Sqflite.firstIntValue(await original.rawQuery('PRAGMA user_version')),6);expect(Sqflite.firstIntValue(await original.rawQuery('SELECT COUNT(*) FROM events')),4);expect((await original.query('events',where:'id=?',whereArgs:['upgrade-sale-00001'])).single['revenue'],777);await original.close();}
    else {expect(repo.state['events'],isEmpty);expect(repo.state['products'],isEmpty);expect(File(path.join(await getDatabasesPath(),'monster-offline.db')).existsSync(),false);}
    await tester.pumpWidget(TrackerApp(repository:repo));await tester.pumpAndSettle();expect(find.text('BUSINESS FUNDS'),findsOneWidget);expect(find.text('Quick actions'),findsOneWidget);
    await binding.convertFlutterSurfaceToImage();await tester.pumpAndSettle();
    for(final theme in themes){final s=clone(repo.state);s['theme']=theme;await repo.save(s);await tester.pumpWidget(TrackerApp(key:ValueKey(theme),repository:repo));await tester.pumpAndSettle();expect(tester.takeException(),isNull);await binding.takeScreenshot('${legacy?'upgrade':'empty'}-${theme.replaceAll(' ','-')}');}
    final s=clone(repo.state);(s['products'] as List).add({'id':'device-product-001','name':'Skincare cream','category':'Skincare','variant':'50 ml','purchaseCost':123,'sellingPrice':555,'minimum':3,'barcode':'00123456789','photo':null});await repo.save(s);
    await repo.append(event(id:'device-restock-001',type:'restock',quantity:9,productId:'device-product-001',cost:1107));
    await repo.append(event(id:'device-sale-00001',type:'sale',quantity:4,productId:'device-product-001',revenue:2220,payment:'cash'));
    await repo.append(event(id:'device-refund-001',type:'refund',target:'device-sale-00001',revenue:555));
    await repo.append(event(id:'device-return-001',type:'return',target:'device-sale-00001',quantity:1));
    expect(validateState(repo.state).book.stock('device-product-001'),6);
    await exerciseProductFlow(tester,repo,screenshot:(name)=>binding.takeScreenshot('${legacy?'upgrade':'empty'}-$name').then((_){}));
    final archivedAgain=clone(repo.state);objects(archivedAgain['products']).firstWhere((p)=>p['id']=='device-product-001')['archived']=true;await repo.save(archivedAgain);
    final large=clone(repo.state);large['businessName']='My skincare business';final photoBytes=List<int>.filled(1600000,42);photoBytes.setAll(0,utf8.encode('%PDF-1.4'));(large['attachments'] as List).add({'id':'large-receipt-0001','eventId':'device-restock-001','mime':'application/pdf','data':base64Encode(photoBytes),'sha256':bytesHash(photoBytes)});await repo.save(large);
    const password='portable-test-password';final encrypted=await Backups.encrypt(repo.state,password),restored=await Backups.decode(encrypted,password);expect(restored,repo.state);
    expect(()=>Backups.decode(encrypted,'wrong-password'),throwsFormatException);
    await Backups.recovery(repo.state,password);final recovery=(await Backups.recoveryFiles()).firstWhere((f)=>f.path.endsWith('.businessbk'));expect(await Backups.decode(await recovery.readAsBytes(),password),repo.state);expect(File('${recovery.path}.partial').existsSync(),false);
    final before=canonical(repo.state);await repo.restore(restored);expect(canonical(repo.state),before);
    await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();await repo.close();
    final reopened=await Repository.open();expect(canonical(reopened.state),before);expect(validateState(reopened.state).book.stock('device-product-001'),0);expect(reopened.state['lastPayment'],'card');final savedProduct=objects(reopened.state['products']).firstWhere((p)=>p['id']=='device-product-001');expect(savedProduct['twoItemPrice'],900);expect(isArchived(savedProduct),true);await reopened.close();
  });
}
