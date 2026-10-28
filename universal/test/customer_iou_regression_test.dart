import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:business_tracker/core/business_modules.dart';
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';
import 'package:business_tracker/business_module_screen.dart';

void main() {
  testWidgets('adding an IOU customer persists it in the business state', (tester) async {
    final initial = emptyState();
    Obj? persisted;
    await tester.pumpWidget(MaterialApp(
      home: BusinessModuleScreen(
        module: moduleCustomerAccounts,
        initialState: initial,
        onSave: (next) async {
          validateState(next);
          persisted = clone(next);
        },
      ),
    ));
    await tester.tap(find.text('Add customer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'IOU test customer');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(persisted, isNotNull);
    final customers = objects(persisted!['customers']);
    expect(customers, hasLength(1));
    expect(customers.single['name'], 'IOU test customer');
    expect(tester.takeException(), isNull);
  });
}
