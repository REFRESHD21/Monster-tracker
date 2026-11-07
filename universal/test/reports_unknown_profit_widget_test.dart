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
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Reports shows incomplete instead of crashing on unknown FIFO cost', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FlutterSecureStorage.setMockInitialValues({});

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final folder = await Directory.systemTemp.createTemp('tracker-reports-null-profit-');
    await databaseFactory.setDatabasesPath(folder.path);
    final repo = await Repository.open();

    try {
      final next = clone(repo.state);
      next['products'] = [
        {
          'id': 'unknown-cost-report-product',
          'name': 'Unknown cost drink',
          'category': 'Drink',
          'variant': '',
          'purchaseCost': null,
          'sellingPrice': 350,
          'minimum': 0,
          'barcode': '',
          'photo': null,
          'archived': false,
        },
      ];
      await repo.save(next);
      await repo.append(event(
        id: 'unknown-cost-report-stock',
        type: 'restock',
        quantity: 1,
        productId: 'unknown-cost-report-product',
        cost: 0,
      ));
      await repo.recordSale(event(
        id: 'unknown-cost-report-sale',
        type: 'sale',
        quantity: 1,
        productId: 'unknown-cost-report-product',
        revenue: 350,
        payment: 'cash',
      ));

      expect(
        objects(validateState(repo.state).salesProfit(objects(repo.state['products']))['products']).single['profit'],
        isNull,
      );

      await tester.pumpWidget(TrackerApp(repository: repo));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Reports').last);
      // TrackerApp performs background sync checks and has periodic work; avoid
      // pumpAndSettle waiting indefinitely for unrelated scheduled frames.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Product profit Incomplete'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await repo.close();
      await folder.delete(recursive: true);
    }
  });
}
