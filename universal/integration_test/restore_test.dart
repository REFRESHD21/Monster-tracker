import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:business_tracker/main.dart';
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';
import 'package:business_tracker/core/legacy.dart';
import 'package:business_tracker/services/repository.dart';

const _active='restore-white-monster';
const _archived='restore-historical-product';

Obj _syntheticLedger() {
  final state=emptyState();
  state['businessId']='synthetic-android-restore-test';
  state['businessName']='Synthetic restore ledger';
  state['products']=[
    {'id':_active,'name':'White Monster','category':'Drink','variant':'500 ml','purchaseCost':208,'sellingPrice':350,'twoItemPrice':600,'minimum':0,'barcode':'','photo':null},
    {'id':_archived,'name':'Need to delete','category':'Drink','variant':'500 ml','purchaseCost':208,'sellingPrice':350,'minimum':0,'barcode':'','photo':null,'archived':true},
  ];
  final events=<Obj>[
    event(id:'fixture-restock-001',type:'restock',quantity:24,productId:_archived,cost:5000,note:'Synthetic opening multipack'),
  ];
  final transfer=event(id:'fixture-transfer-01',type:'transfer',quantity:17,note:'Synthetic flavour transfer');
  transfer['from']=_archived;
  transfer['to']=_active;
  events.add(transfer);
  events.addAll([
    event(id:'fixture-deal-00001',type:'deal',quantity:2,productId:_active,revenue:600,payment:'cash',note:'Historical 2 for 6'),
    event(id:'fixture-sale-00001',type:'sale',quantity:2,productId:_active,revenue:600,payment:'cash',note:'Synthetic sale one'),
    event(id:'fixture-sale-00002',type:'sale',quantity:2,productId:_active,revenue:600,payment:'card',note:'Synthetic sale two'),
    event(id:'fixture-missing-001',type:'missing',quantity:4,productId:_archived,note:'Synthetic missing stock'),
    event(id:'fixture-damaged-01',type:'damaged',quantity:1,productId:_archived,note:'Synthetic damaged stock'),
  ]);
  state['events']=events;
  return state;
}

Future<void> _openRestore(WidgetTester tester) async {
  await tester.tap(find.descendant(of:find.byType(NavigationBar),matching:find.text('Settings')));
  await tester.pumpAndSettle();
  final action=find.text('Import / restore backup');
  await Scrollable.ensureVisible(tester.element(action),alignment:.5);
  await tester.pumpAndSettle();
  await tester.tap(action);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('synthetic backup restores through app UI with FIFO and archive history', (tester) async {
    final repo=await Repository.open();
    expect(repo.state['events'],isEmpty,reason:'The disposable emulator was cleared before restore.');
    expect(repo.state['products'],isEmpty);
    final original=_syntheticLedger();
    final valid=Uint8List.fromList(utf8.encode(encodeBackup(original)));
    Uint8List selected=valid;
    await tester.pumpWidget(TrackerApp(repository:repo,pickBackupBytes:()async=>selected));
    await tester.pumpAndSettle();

    await _openRestore(tester);
    expect(find.text('Review restore'),findsOneWidget);
    expect(find.textContaining('2 products'),findsOneWidget);
    expect(find.textContaining('7 history records'),findsOneWidget);
    expect(find.textContaining('Revenue \\$18.00'),findsOneWidget);
    expect(find.textContaining('Inventory \\$27.11'),findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton,'Restore'));
    await tester.pumpAndSettle();

    expect(repo.state['businessName'],'Synthetic restore ledger');
    expect(objects(repo.state['products']).length,2);
    expect(objects(repo.state['events']).length,7);
    final accounts=validateState(repo.state),summary=accounts.summary();
    expect(accounts.book.stock(_active),11);
    expect(accounts.book.stock(_archived),2);
    expect(accounts.book.stock(_active)+accounts.book.stock(_archived),13);
    expect(summary['revenue'],1800);
    expect(summary['cogs'],1248);
    expect(summary['losses'],1041);
    expect(summary['inventoryValue'],2711);
    expect(summary['netProfit'],-489);
    expect(summary['cogs']+summary['losses']+summary['inventoryValue'],5000);
    final saleLots=accounts.history['fixture-deal-00001']!.lots;
    expect(saleLots.fold<int>(0,(sum,lot)=>sum+lot.cost),416);
    expect(accounts.history['fixture-transfer-01']!.rows.fold<int>(0,(sum,row)=>sum+row['revenue'] as int),0);
    final projection=accounts.salesProfit(objects(repo.state['products']));
    expect(projection['revenue'],1800);
    expect(projection['profit'],552);
    expect(projection['futureRevenue'],3850);
    expect(projection['futureCost'],2293);
    expect(projection['futureProfit'],1557);
    expect(objects(projection['products']).firstWhere((p)=>p['productId']==_archived)['remaining'],0);
    expect(objects(repo.state['events']).where((e)=>e['type']=='transfer').single['to'],_active);

    // A root checksum mismatch must be rejected by the same restore UI before
    // persistence. Keep the accepted ledger byte-for-byte unchanged.
    final beforeTamper=canonical(repo.state),root=obj(strictJson(utf8.decode(valid)));
    obj(root['state'])['businessName']='Tampered synthetic record';
    selected=Uint8List.fromList(utf8.encode(canonical(root)));
    await _openRestore(tester);
    expect(find.text('Action incomplete · local records retained'),findsOneWidget);
    expect(find.textContaining('Backup checksum failed'),findsOneWidget);
    expect(canonical(repo.state),beforeTamper);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of:find.byType(NavigationBar),matching:find.text('Products')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archived products'));
    await tester.pumpAndSettle();
    expect(find.text('Need to delete'),findsOneWidget);
    expect(find.widgetWithText(TextButton,'Restore'),findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await repo.close();
    final reopened=await Repository.open();
    expect(canonical(reopened.state),beforeTamper);
    final restored=validateState(reopened.state);
    expect(restored.book.stock(_active)+restored.book.stock(_archived),13);
    expect(restored.summary()['netProfit'],-489);
    await reopened.close();
  });
}
