import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';
import 'package:business_tracker/core/legacy.dart';
void main() {
  test('100 independent Java oracle histories preserve FIFO, fees, losses and corrections', () {
    final cases = strictJson(File('test/fixtures/java-parity.json').readAsStringSync()) as List;
    for(final c in cases) {final state=importLegacy(canonical(c['backup']));final a=validateState(state), totals=a.summary();for(final k in obj(c['expected']).keys) {expect(k=='stock'?a.book.stock(legacyProduct):totals[k],c['expected'][k],reason:'scenario ${cases.indexOf(c)}, $k');}expect(decodeBackup(encodeBackup(state)),state);}
  });
  test('new installation is empty and accepts any quantity without opening seeds', () {
    final s=emptyState();expect(validateState(s).book.value,0);
    s['products']=[product()];s['events']=[event(id:'restock-test-001',type:'restock',quantity:30,productId:'product-test-001',cost:3001),event(id:'sale-test-00001',type:'sale',quantity:7,productId:'product-test-001',revenue:2450,payment:'cash')];
    final a=validateState(s);expect(a.book.stock('product-test-001'),23);expect(a.summary()['cogs'],700);expect(a.summary()['netProfit'],1750);
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
  test('cents never round; six themes supported', () {expect(cents('12.01'),1201);expect(()=>cents('0.001'),throwsFormatException);expect(themes.length,6);});
}
Obj product() => {'id':'product-test-001','name':'Moisturiser','category':'Skincare','variant':'50 ml','purchaseCost':100,'sellingPrice':350,'minimum':5,'barcode':'0012345','photo':null};
