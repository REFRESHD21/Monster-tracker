import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';
import 'package:business_tracker/main.dart';
import 'package:business_tracker/services/repository.dart';

void main() {
  testWidgets('home Add stock saves a restock and updates available inventory', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FlutterSecureStorage.setMockInitialValues({});

    await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfiNoIsolate;
      final folder = await Directory.systemTemp.createTemp('tracker-restock-regression-');
      await databaseFactory.setDatabasesPath(folder.path);
      final repo = await Repository.open();
      try {
        final next = clone(repo.state);
        (next['products'] as List).add({
          'id': 'stock-test-product',
          'name': 'Mango',
          'category': 'Drink',
          'variant': '',
          'purchaseCost': 200,
          'sellingPrice': 350,
          'minimum': 0,
          'barcode': '',
          'photo': null,
          'archived': false,
        });
        await repo.save(next);

        await tester.pumpWidget(TrackerApp(repository: repo));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add stock'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mango'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).at(0), '3');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm save'));
        await tester.pumpAndSettle();

        expect(validateState(repo.state).book.stock('stock-test-product'), 3);
        expect(objects(repo.state['events']).where((e) => e['type'] == 'restock').length, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await repo.close();
        await folder.delete(recursive: true);
      }
    });
  });
}
