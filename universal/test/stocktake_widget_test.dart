import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';
import 'package:business_tracker/services/repository.dart';
import 'package:business_tracker/main.dart';

void main() {
  testWidgets('stocktake UI previews sellable and damaged counts before confirmation', (tester) async {
    tester.view.physicalSize=const Size(390,844);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FlutterSecureStorage.setMockInitialValues({});
    await tester.runAsync(() async {
      sqfliteFfiInit();databaseFactory=databaseFactoryFfiNoIsolate;
      final folder=await Directory.systemTemp.createTemp('tracker-stocktake-ui-');
      await databaseFactory.setDatabasesPath(folder.path);
      final repo=await Repository.open();
      try {
        final next=clone(repo.state);
        next['products']=[{'id':'stocktake-ui-product-01','name':'Cola','category':'Monster','variant':'500 ml','purchaseCost':100,'sellingPrice':300,'minimum':0,'barcode':'','photo':null}];
        await repo.save(next);
        await repo.append(event(id:'stocktake-ui-restock-01',type:'restock',quantity:5,productId:'stocktake-ui-product-01',cost:500));
        await tester.pumpWidget(TrackerApp(repository:repo));await tester.pumpAndSettle();
        await tester.tap(find.descendant(of:find.byType(NavigationBar),matching:find.text('Products')));await tester.pumpAndSettle();
        await tester.tap(find.text('Stocktake mode'));await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('start-stocktake')));await tester.pumpAndSettle();
        final id=objects(repo.state['stocktakes']).single['id'] as String;
        await tester.tap(find.byKey(ValueKey('open-stocktake-$id')));await tester.pumpAndSettle();
        await tester.tap(find.text('Count'));await tester.pumpAndSettle();
        final fields=find.byType(TextField);await tester.enterText(fields.at(0),'3');await tester.enterText(fields.at(1),'1');
        await tester.tap(find.byKey(const ValueKey('save-stocktake-count')));await tester.pumpAndSettle();
        expect(find.textContaining('Counted sellable 3 + damaged 1'),findsOneWidget);
        expect(find.textContaining('variance -1'),findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('confirm-stocktake')));await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm adjustments'));await tester.pumpAndSettle();
        expect(repo.state['stocktakes'].single['status'],'completed');
        expect(validateState(repo.state).book.stock('stocktake-ui-product-01'),3);
        expect(validateState(repo.state).summary()['revenue'],0);
        expect(tester.takeException(),isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
        await repo.close();await folder.delete(recursive:true);
      }
    });
  });
}
