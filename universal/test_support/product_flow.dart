import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:business_tracker/main.dart';
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';
import 'package:business_tracker/core/products.dart';
import 'package:business_tracker/services/repository.dart';

// The same UI assertions run with SQLite on the host and on the Android device.
Future<void> exerciseProductFlow(WidgetTester tester, Repository repo,
    {required Future<void> Function(String) screenshot}) async {
  Future<void> tapVisible(Finder target) async {
    if(target.evaluate().isEmpty){
      // Scroll the page's primary list. The last Scrollable can be an internal
      // navigation widget and may disappear while the test changes tabs.
      await tester.scrollUntilVisible(target,150,scrollable:find.byType(Scrollable).first);
    }
    await Scrollable.ensureVisible(tester.element(target), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }
    // Exercise the compact sale UI against the upgraded SQLite repository.
    final configured=clone(repo.state);
    (configured['products'] as List).add({'id':'unused-product-001','name':'Unused flavour','category':'Drinks','variant':'','purchaseCost':0,'sellingPrice':300,'minimum':0,'barcode':'','photo':null});
    await repo.save(configured);
    await tester.pumpWidget(TrackerApp(key:const ValueKey('fast-sales'),repository:repo));await tester.pumpAndSettle();
    await tester.tap(find.descendant(of:find.byType(NavigationBar),matching:find.text('Products')));await tester.pumpAndSettle();expect(find.text('Active products'),findsOneWidget);
    await tapVisible(find.byKey(const ValueKey('product-options-device-product-001')));
    await tapVisible(find.text('Edit product / prices'));
    final dealField=find.byWidgetPredicate((w)=>w is TextField && w.decoration?.labelText=='Optional 2-item deal TOTAL (AUD; blank disables)');
    await Scrollable.ensureVisible(tester.element(dealField), alignment: .5);await tester.pumpAndSettle();await tester.enterText(dealField,'9.00');
    await tester.tap(find.text('Save product'));await tester.pumpAndSettle();
    expect(objects(repo.state['products']).firstWhere((p)=>p['id']=='device-product-001')['twoItemPrice'],900);
    final historyBefore=objects(repo.state['events']).length;
    await tester.tap(find.byKey(const ValueKey('record-sale')));await tester.pumpAndSettle();
    await tapVisible(find.descendant(of:find.byType(BottomSheet),matching:find.text('Skincare cream · 50 ml')));
    await tapVisible(find.text('2-item deal · \$9.00'));
    await tapVisible(find.text('Card / bank'));
    await screenshot('fast-deal');
    await tester.tap(find.byKey(const ValueKey('confirm-sale')));await tester.tap(find.byKey(const ValueKey('confirm-sale')));
    await tester.pumpAndSettle();
    expect(objects(repo.state['events']).length,historyBefore+1);expect(objects(repo.state['events']).last['revenue'],900);expect(repo.state['lastPayment'],'card');
    final retry=event(id:'duplicate-sale-001',type:'sale',quantity:1,productId:'device-product-001',revenue:555,payment:'card');
    await Future.wait([repo.recordSale(retry),repo.recordSale(retry)]);expect(await repo.recordSale(retry),false);
    expect(objects(repo.state['events']).where((e)=>e['id']=='duplicate-sale-001').length,1);
    expect(validateState(repo.state).book.stock('device-product-001'),3);
    await tester.tap(find.byKey(const ValueKey('record-sale')));await tester.pumpAndSettle();await tapVisible(find.descendant(of:find.byType(BottomSheet),matching:find.text('Skincare cream · 50 ml')));
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip,'Card / bank')).selected,true);
    await tester.tap(find.text('Cancel'));await tester.pumpAndSettle();
    // Exercise the removal dialogs, including stock blockers and true deletion.
    expect(productRemoval(repo.state,'device-product-001').canArchive,false);
    await tapVisible(find.byKey(const ValueKey('product-options-device-product-001')));
    await tapVisible(find.text('Remove / archive product'));
    expect(find.textContaining('3 units remain'),findsOneWidget);expect(find.widgetWithText(FilledButton,'Archive product'),findsNothing);
    await tester.tap(find.text('Cancel'));await tester.pumpAndSettle();
    await repo.append(event(id:'remaining-loss-001',type:'damaged',quantity:3,productId:'device-product-001',note:'Device removal fixture'));
    final beforeArchive=validateState(repo.state).summary();
    await tapVisible(find.byKey(const ValueKey('product-options-device-product-001')));
    await tapVisible(find.text('Remove / archive product'));
    await tester.tap(find.widgetWithText(FilledButton,'Archive product'));await tester.pumpAndSettle();
    expect(validateState(repo.state).summary(),beforeArchive);expect(find.text('Skincare cream · 50 ml'),findsNothing);
    await tapVisible(find.byKey(const ValueKey('product-options-unused-product-001')));
    await tapVisible(find.text('Remove / archive product'));
    await tester.tap(find.text('Delete permanently'));await tester.pumpAndSettle();expect(objects(repo.state['products']).any((p)=>p['id']=='unused-product-001'),false);
    // The archive toggle is above the product cards; return the list to its
    // start before asking scrollUntilVisible to reveal that header control.
    await tester.drag(find.byType(Scrollable).first,const Offset(0,1000));await tester.pumpAndSettle();
    await tapVisible(find.text('Archived products'));expect(find.text('Skincare cream · 50 ml'),findsOneWidget);
    await screenshot('archived-products');
    await tapVisible(find.text('Restore'));expect(isArchived(objects(repo.state['products']).firstWhere((p)=>p['id']=='device-product-001')),false);
}
