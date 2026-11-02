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
  testWidgets('reproduces Reports null-profit crash with unknown FIFO cost', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FlutterSecureStorage.setMockInitialValues({});

    await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfiNoIsolate;
      final folder = await Directory.systemTemp.createTemp('tracker-reports-null-');
      await databaseFactory.setDatabasesPath(folder.path);
      final repo = await Repository.open();
      try {
        final next = clone(repo.state);
        (next['products'] as List).add({
          'id': 'report-test-drink',
          'name': 'Unknown-cost drink',
          'category': 'Drink',
          'variant': '',
          'purchaseCost': null,
          'sellingPrice': 350,
          'minimum': 0,
          'barcode': '',
          'photo': null,
          'archived': false,
        });
        (next['events'] as List).addAll([
          event(
            id: 'restock-test-001',
            type: 'restock',
            quantity: 1,
            productId: 'report-test-drink',
            cost: 0,
          ),
          event(
            id: 'sale-test-0001',
            type: 'sale',
            quantity: 1,
            productId: 'report-test-drink',
            revenue: 350,
            payment: 'cash',
          ),
        ]);
        await repo.save(next);

        await tester.pumpWidget(TrackerApp(repository: repo));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reports'));
        await tester.pumpAndSettle();

        // The accounting engine correctly marks this profit as unknown.
        final report = validateState(repo.state);
        final productSales = report.salesProfit(objects(repo.state['products']));
        final productRow = objects(productSales['products'])
            .singleWhere((row) => row['productId'] == 'report-test-drink');
        expect(productRow['profit'], isNull);

        // The Reports screen formats that null with money(int), which throws.
        expect(tester.takeException(), isA<TypeError>());
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await repo.close();
        await folder.delete(recursive: true);
      }
    });
  });
}

  testWidgets('catalogue editor survives repeated open and cancel cycles', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FlutterSecureStorage.setMockInitialValues({});

    await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfiNoIsolate;
      final folder = await Directory.systemTemp.createTemp('tracker-catalogue-stress-');
      await databaseFactory.setDatabasesPath(folder.path);
      final repo = await Repository.open();
      try {
        final next = clone(repo.state);
        (next['products'] as List).add({
          'id': 'catalogue-test-drink',
          'name': 'Test drink',
          'category': 'Drink',
          'variant': 'Original',
          'purchaseCost': 100,
          'sellingPrice': 350,
          'minimum': 0,
          'barcode': '',
          'photo': null,
          'archived': false,
        });
        await repo.save(next);
        await tester.pumpWidget(TrackerApp(repository: repo));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Products'));
        await tester.pumpAndSettle();

        for (var i = 0; i < 25; i++) {
          await tester.tap(find.byKey(const ValueKey('product-options-catalogue-test-drink')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Edit product / prices'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Catalogue editor cycle $i');
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await repo.close();
        await folder.delete(recursive: true);
      }
    });
  });

}
