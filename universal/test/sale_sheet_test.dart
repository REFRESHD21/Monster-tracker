import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/sale_sheet.dart';

Obj product({int? deal}) => {'id':'flavour-test-001','name':'Mango','variant':'500 ml','sellingPrice':350,if(deal!=null)'twoItemPrice':deal};
Future<void> open(WidgetTester t,Obj p,Future<void> Function(Obj,Obj?) save,{String payment='cash'}) async {
  t.view.physicalSize=const Size(420,900);t.view.devicePixelRatio=1;
  addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(c)=>TextButton(onPressed:()=>showModalBottomSheet<bool>(context:c,isScrollControlled:true,builder:(_)=>SaleSheet(product:p,stock:20,payment:payment,onSave:save,pickReceipt:()async=>null)),child:const Text('Open'))))));
  await t.tap(find.text('Open'));await t.pumpAndSettle();
}
void main(){
  testWidgets('deal quantity total and remembered payment share one confirmation; rapid taps save once',(t)async{
    final gate=Completer<void>();final saves=<Obj>[];
    await open(t,product(deal:600),(e,a)async{saves.add(e);await gate.future;},payment:'card');
    expect(find.text('Quantity'),findsOneWidget);expect(find.text('Total (AUD)'),findsOneWidget);
    expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip,'Card / bank')).selected,true);
    await t.tap(find.text('2-item deal · \$6.00'));await t.pump();
    expect(t.widget<TextField>(find.byType(TextField).at(0)).controller!.text,'2');
    expect(t.widget<TextField>(find.byType(TextField).at(1)).controller!.text,'6.00');
    await t.tap(find.byKey(const ValueKey('confirm-sale')));await t.tap(find.byKey(const ValueKey('confirm-sale')));await t.pump();
    expect(saves.length,1);expect(saves.single['quantity'],2);expect(saves.single['revenue'],600);expect(saves.single['payment'],'card');
    expect(saves.single['productName'],'Mango · 500 ml');
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('confirm-sale'))).onPressed,null);
    gate.complete();await t.pumpAndSettle();expect(find.byType(SaleSheet),findsNothing);
  });
  testWidgets('product with no deal has no deal button; custom quantity uses its own normal price',(t)async{
    Obj? saved;await open(t,product(),(e,a)async{saved=e;});
    expect(find.textContaining('2-item deal ·'),findsNothing);
    await t.enterText(find.byType(TextField).at(0),'3');await t.pump();
    expect(t.widget<TextField>(find.byType(TextField).at(1)).controller!.text,'10.50');
    await t.tap(find.text('Card / bank'));await t.pump();
    await t.tap(find.byKey(const ValueKey('confirm-sale')));await t.pumpAndSettle();
    expect(saved!['quantity'],3);expect(saved!['revenue'],1050);expect(saved!['payment'],'card');
  });
  testWidgets('invalid quantity and failed save remain editable without creating another draft',(t)async{
    final ids=<String>[],entries=<String>[];await open(t,product(),(e,a)async{ids.add(e['id']);entries.add(canonical(e));throw const FormatException('Storage unavailable');});
    await t.enterText(find.byType(TextField).at(0),'21');await t.tap(find.byKey(const ValueKey('confirm-sale')));await t.pumpAndSettle();expect(ids,isEmpty);expect(find.textContaining('Not enough stock'),findsOneWidget);
    await t.enterText(find.byType(TextField).at(0),'1');await t.tap(find.byKey(const ValueKey('confirm-sale')));await t.pumpAndSettle();expect(find.text('Storage unavailable'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('confirm-sale')));await t.pumpAndSettle();expect(ids.length,2);expect(ids.toSet().length,1);expect(entries.toSet().length,1);
  });
  testWidgets('mixed bundle and individual cart records one revenue-bearing sale with component allocations',(t)async{
    Obj? saved;
    final bundle=<String,dynamic>{'id':'cart-bundle-001','name':'Starter set','sellingPrice':500,'components':[{'productId':'component-a-001','quantity':1},{'productId':'component-b-001','quantity':2}]};
    final lines=<Obj>[
      {'kind':'bundle','id':'cart-bundle-001','name':'Starter set','quantity':1,'unitPrice':500,'bundle':bundle},
      {'kind':'product','id':'individual-c-001','name':'Extra item','quantity':2,'unitPrice':350},
    ];
    final cartProduct=<String,dynamic>{'id':'cart','name':'Sale cart','variant':'','sellingPrice':1200};
    t.view.physicalSize=const Size(420,900);t.view.devicePixelRatio=1;
    addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(c)=>TextButton(onPressed:()=>showModalBottomSheet<bool>(context:c,isScrollControlled:true,builder:(_)=>SaleSheet(product:cartProduct,cartLines:lines,stock:100,payment:'cash',onSave:(e,a)async{saved=e;},pickReceipt:()async=>null)),child:const Text('Open cart'))))));
    await t.tap(find.text('Open cart'));await t.pumpAndSettle();
    expect(find.text('1 × Starter set · $5.00'),findsOneWidget);
    expect(find.text('2 × Extra item · $7.00'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('confirm-sale')));await t.pumpAndSettle();
    expect(saved!['revenue'],1200);
    expect(saved!['bundleId'],'cart-bundle-001');
    expect(saved!['allocations'],[
      {'productId':'component-a-001','quantity':1},
      {'productId':'component-b-001','quantity':2},
      {'productId':'individual-c-001','quantity':2},
    ]);
    expect(saved!['standaloneAllocations'],[{'productId':'individual-c-001','quantity':2}]);
  });
}
