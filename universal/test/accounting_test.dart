import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';
import 'package:business_tracker/core/legacy.dart';
void main() {
  test('write limits match portable reader limits before replay',(){final s=emptyState();s['events']=List.filled(100001,<String,dynamic>{});expect(()=>validateState(s),throwsA(isA<FormatException>().having((e)=>e.message,'message',contains('History limit'))));});
  test('large SQLite chunks preserve Unicode across platform UTF-8 messages',(){
    final text='${'x'*131071}😀 café after';
    expect(stateChunks(text).map((part)=>utf8.decode(utf8.encode(part))).join(),text);
  });
  test('CSV keeps refund amounts numeric and neutralizes user formulas',(){
    expect(csvCell(-300),'"-300"');expect(csvCell('=IMPORTXML("bad")'),'"\'=IMPORTXML(""bad"")"');
  });
  test('Perth ranges use exclusive ends, Monday weeks and July financial year',(){
    final day=reportRange('day',DateTime.parse('2026-10-14T18:00:00Z'));
    expect(day.$1,DateTime.parse('2026-10-14T16:00:00Z').millisecondsSinceEpoch);
    expect(day.$2,DateTime.parse('2026-10-15T16:00:00Z').millisecondsSinceEpoch);
    final fy=reportRange('financial year',DateTime.parse('2026-02-01T00:00:00Z'));
    expect(fy.$1,DateTime.parse('2025-06-30T16:00:00Z').millisecondsSinceEpoch);
    expect(fy.$2,DateTime.parse('2026-06-30T16:00:00Z').millisecondsSinceEpoch);
  });
  test('identifying historical stock transfers original FIFO cost without profit',(){
    final a=calculate([event(id:'restock-test-001',type:'restock',quantity:3,productId:legacyProduct,cost:1000),{...event(id:'transfer-test-001',type:'transfer',quantity:2),'from':legacyProduct,'to':'product-test-001'}]);
    expect(a.book.stock(legacyProduct),1);expect(a.book.stock('product-test-001'),2);expect(a.book.value,1000);expect(a.summary()['netProfit'],0);
  });
  test('correcting one of several GST refunds recomputes cumulative rounding',(){
    final a=calculate([event(id:'restock-test-001',type:'restock',quantity:2,productId:'product-test-001',cost:200),event(id:'sale-test-00001',type:'sale',quantity:2,productId:'product-test-001',revenue:600,payment:'cash',outputGst:55),event(id:'refund-test-001',type:'refund',target:'sale-test-00001',revenue:300),event(id:'refund-test-002',type:'refund',target:'sale-test-00001',revenue:300),event(id:'correct-test-001',type:'undo',target:'refund-test-001',note:'Entry mistake')]);
    expect(a.summary()['revenue'],300);expect(a.summary()['outputGst'],28);
  });
  test('100 independent Java oracle histories preserve FIFO, fees, losses and corrections', () {
    final cases = strictJson(File('test/fixtures/java-parity.json').readAsStringSync()) as List;
    for(final c in cases) {final state=importLegacy(canonical(c['backup']));final a=validateState(state), totals=a.summary();for(final k in obj(c['expected']).keys) {expect(k=='stock'?a.book.stock(legacyProduct):totals[k],c['expected'][k],reason:'scenario ${cases.indexOf(c)}, $k');}expect(decodeBackup(encodeBackup(state)),state);}
  });
  test('new installation is empty and accepts any quantity without opening seeds', () {
    final s=emptyState();expect(validateState(s).book.value,0);
    s['products']=[product()];s['events']=[event(id:'restock-test-001',type:'restock',quantity:30,productId:'product-test-001',cost:3001),event(id:'sale-test-00001',type:'sale',quantity:7,productId:'product-test-001',revenue:2450,payment:'cash')];
    final a=validateState(s);expect(a.book.stock('product-test-001'),23);expect(a.summary()['cogs'],700);expect(a.summary()['netProfit'],1750);
  });
  test('sales and product profit use actual prices, FIFO costs, refunds and physical returns',(){
    final products=[product()..['sellingPrice']=500];
    final events=[event(id:'profit-stock-001',type:'restock',quantity:2,productId:'product-test-001',cost:300),event(id:'profit-stock-002',type:'restock',quantity:1,productId:'product-test-001',cost:250),event(id:'profit-sale-00001',type:'sale',quantity:2,productId:'product-test-001',revenue:500,payment:'cash'),event(id:'profit-sale-00002',type:'sale',quantity:1,productId:'product-test-001',revenue:100,payment:'cash'),event(id:'profit-refund-001',type:'refund',target:'profit-sale-00001',revenue:100),event(id:'profit-return-001',type:'return',target:'profit-sale-00001',quantity:1)];
    final a=calculate(events),p=a.salesProfit(products);
    expect(p['revenue'],500);expect(p['cogs'],400);expect(p['profit'],100);expect(p['unitsSold'],2);
    expect(p['futureRevenue'],500);expect(p['futureCost'],150);expect(p['futureProfit'],350);expect(p['totalRevenue'],1000);expect(p['totalProfit'],450);
    final line=objects(p['products']).single;expect(line['revenue'],500);expect(line['profit'],100);expect(line['remaining'],1);
  });
  test('damaged stock and business expenses do not alter sales product profit',(){
    final s=emptyState();s['products']=[product()..['sellingPrice']=500];s['events']=[event(id:'damage-stock-001',type:'restock',quantity:2,productId:'product-test-001',cost:300),event(id:'damage-sale-0001',type:'sale',quantity:1,productId:'product-test-001',revenue:100,payment:'cash'),event(id:'damage-writeoff-01',type:'damaged',quantity:1,productId:'product-test-001'),event(id:'damage-expense-001',type:'expense',cost:900)];
    final a=validateState(s),p=a.salesProfit(objects(s['products']));expect(p['revenue'],100);expect(p['cogs'],150);expect(p['profit'],-50);expect(p['futureRevenue'],0);expect(p['futureProfit'],0);expect(a.summary()['netProfit'],-1100);
  });
  test('no sales with stock shows future potential and missing cost is flagged',(){
    final s=emptyState();s['products']=[product()..['sellingPrice']=350];s['events']=[event(id:'no-sale-stock-001',type:'restock',quantity:2,productId:'product-test-001',cost:0)];
    final p=validateState(s).salesProfit(objects(s['products']));expect(p['revenue'],0);expect(p['profit'],0);expect(p['futureRevenue'],700);expect(p['futureProfit'],isNull);expect(p['totalProfit'],isNull);expect(p['unknownCostUnits'],2);expect(objects(p['products']).single['unitsSold'],0);
  });
  test('sold units with zero FIFO cost and configured nonzero cost mark profit incomplete',(){
    final s=emptyState();s['products']=[product()];s['events']=[event(id:'unknown-cost-stock1',type:'restock',quantity:1,productId:'product-test-001',cost:0),event(id:'unknown-cost-sale1',type:'sale',quantity:1,productId:'product-test-001',revenue:350,payment:'cash')];
    final p=validateState(s).salesProfit(objects(s['products']));expect(p['revenue'],350);expect(p['profit'],isNull);expect(p['unknownEarnedCostUnits'],1);expect(objects(p['products']).single['profit'],isNull);
  });
  test('full refund reverses recorded revenue and discounts remain actual; future uses current price',(){
    final products=[product()..['sellingPrice']=300];
    final events=[event(id:'refund-stock-0001',type:'restock',quantity:2,productId:'product-test-001',cost:200),event(id:'refund-sale-00001',type:'sale',quantity:1,productId:'product-test-001',revenue:180,payment:'cash'),event(id:'refund-part-00001',type:'refund',target:'refund-sale-00001',revenue:80),event(id:'refund-part-00002',type:'refund',target:'refund-sale-00001',revenue:100)];
    final a=calculate(events),first=a.salesProfit(products);expect(first['revenue'],0);expect(first['profit'],-100);expect(first['futureRevenue'],300);
    products.single['sellingPrice']=450;final updated=a.salesProfit(products);expect(updated['revenue'],0);expect(updated['futureRevenue'],450);expect(updated['futureProfit'],350);expect(updated['totalRevenue'],450);
  });
  test('refund retains sale fees; return restores original FIFO value; cannot overrefund/return', () {
    final events=[event(id:'restock-test-001',type:'restock',quantity:3,productId:'product-test-001',cost:1000),event(id:'sale-test-00001',type:'sale',quantity:3,productId:'product-test-001',revenue:1500,fee:30,payment:'card'),event(id:'refund-test-001',type:'refund',target:'sale-test-00001',revenue:500),event(id:'return-test-001',type:'return',quantity:1,target:'sale-test-00001')];
    final a=calculate(events);expect(a.book.value,333);expect(a.summary()['revenue'],1000);expect(a.summary()['fees'],30);expect(a.summary()['cogs'],667);
    expect(()=>calculate([...events,event(id:'refund-test-002',type:'refund',target:'sale-test-00001',revenue:1001)]),throwsFormatException);
    expect(()=>calculate([...events,event(id:'return-test-002',type:'return',target:'sale-test-00001',quantity:3)]),throwsFormatException);
  });
  test('overselling, duplicate IDs, conflict and tampering leave source unchanged', () {
    final s=emptyState();s['products']=[product()];final text=canonical(s);
    expect(()=>calculate([event(id:'sale-test-00001',type:'sale',quantity:1,productId:'product-test-001',revenue:100,payment:'cash')]),throwsFormatException);expect(canonical(s),text);
    final backup=encodeBackup(s);expect(()=>decodeBackup(backup.replaceFirst('My business','Other business')),throwsFormatException);
    expect(()=>strictJson('{"a":1,"a":2}'),throwsFormatException);
  });
  test('legacy dates, raw backups and repeat imports are preserved', () {
    final c=(strictJson(File('test/fixtures/java-parity.json').readAsStringSync()) as List).first;
    final s=importLegacy(canonical(c['backup']));expect(s['events'][0]['date'],null);expect(s['legacy'],c['backup']);expect(mergeBackup(s,s),s);
    final wrong=clone(s);wrong['events'][2]['cost']=12345;expect(()=>mergeBackup(s,wrong),throwsFormatException);
  });
  test('archived stock stays in FIFO inventory but is excluded from sellable future estimates',(){
    final archived={'id':'archived-product-001','name':'Historical flavour','category':'Drink','variant':'500 ml','purchaseCost':250,'sellingPrice':400,'minimum':0,'barcode':'','photo':null,'archived':true};
    final events=[event(id:'archive-stock-001',type:'restock',quantity:2,productId:'archived-product-001',cost:500)];
    final accounts=calculate(events),potential=accounts.salesProfit([archived]);
    expect(accounts.book.stock('archived-product-001'),2);
    expect(accounts.book.value,500);
    expect(potential['futureRevenue'],0);
    expect(potential['futureCost'],0);
    expect(potential['futureProfit'],0);
    expect(objects(potential['products']).single['remaining'],0);
  });
  test('cents never round; six themes supported', () {expect(cents('12.01'),1201);expect(()=>cents('0.001'),throwsFormatException);expect(themes.length,6);});
}
Obj product() => {'id':'product-test-001','name':'Moisturiser','category':'Skincare','variant':'50 ml','purchaseCost':100,'sellingPrice':350,'minimum':5,'barcode':'0012345','photo':null};
