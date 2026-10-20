import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:business_tracker/core/business_modules.dart';
import 'package:business_tracker/services/repository.dart';
import 'package:business_tracker/main.dart';

void main() {
  testWidgets('each optional module switch persists independently and controls home visibility', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FlutterSecureStorage.setMockInitialValues({});

    await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfiNoIsolate;
      final folder = await Directory.systemTemp.createTemp('tracker-modules-ui-');
      await databaseFactory.setDatabasesPath(folder.path);
      var repo = await Repository.open();
      var repoClosed = false;
      try {
        await tester.pumpWidget(TrackerApp(repository: repo));
        await tester.pumpAndSettle();

        Future<void> openSettings() async {
          await tester.tap(find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Settings'),
          ));
          await tester.pumpAndSettle();
        }

        final enabled = <String>{};
        for (final key in moduleKeys) {
          final toggle = find.byKey(ValueKey('module-toggle-' + key));
          await openSettings();
          await tester.ensureVisible(toggle);
          await tester.pumpAndSettle();
          await tester.tap(toggle);
          await tester.pump();
          await tester.pumpAndSettle();

          enabled.add(key);
          for (final candidate in moduleKeys) {
            expect(
              moduleEnabled(repo.state, candidate),
              enabled.contains(candidate),
              reason: '$key unexpectedly changed $candidate',
            );
          }
        }

        await tester.tap(find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Home'),
        ));
        await tester.pumpAndSettle();
        for (final key in moduleKeys) {
          await tester.scrollUntilVisible(find.text(moduleNames[key]!), 250, scrollable: find.byType(Scrollable).first);
          await tester.pumpAndSettle();
          expect(find.text(moduleNames[key]!), findsOneWidget);
        }

        await openSettings();
        final disabled = moduleKeys.first;
        final toggle = find.byKey(ValueKey('module-toggle-' + disabled));
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pump();
        await tester.pumpAndSettle();

        expect(moduleEnabled(repo.state, disabled), isFalse);
        for (final other in moduleKeys.skip(1)) {
          expect(moduleEnabled(repo.state, other), isTrue);
        }
        await tester.tap(find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Home'),
        ));
        await tester.pumpAndSettle();
        expect(find.text(moduleNames[disabled]!), findsNothing);
        for (final other in moduleKeys.skip(1)) {
          await tester.scrollUntilVisible(find.text(moduleNames[other]!), 250, scrollable: find.byType(Scrollable).first);
          await tester.pumpAndSettle();
          expect(find.text(moduleNames[other]!), findsOneWidget);
        }

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await repo.close();
        repoClosed = true;
        repo = await Repository.open();
        repoClosed = false;
        for (final key in moduleKeys) {
          expect(moduleEnabled(repo.state, key), key != disabled);
        }
        await repo.close();
        repoClosed = true;
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        if (!repoClosed) await repo.close();
        await folder.delete(recursive: true);
      }
    });
  });
}
