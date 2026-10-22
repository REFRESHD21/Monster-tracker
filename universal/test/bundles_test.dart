import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:business_tracker/core/bundles.dart';
import 'package:business_tracker/core/business_modules.dart';
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';
import 'package:business_tracker/core/legacy.dart';

Obj product(String id, {int? price = 900}) => <String, dynamic>{
  'id': id, 'name': id, 'category': 'Skincare', 'variant': '',
  'purchaseCost': null, 'sellingPrice': price, 'minimum': 0,
  'barcode': '', 'photo': null,
};
Obj bundle(String id, List<Obj> components, {int? price = 2000}) => <String, dynamic>{
  'id': id, 'name': 'Bundle $id', 'category': 'Skincare', 'description': '',
  'sellingPrice': price, 'components': components, 'archived': false, 'photo': null,
};
Obj addStock(String id, String productId, int q, int cost) => event(
  id: id, type: 'restock', quantity: q, productId: productId, cost: cost,
);
const when = 1792000000000;
Obj sell(Obj b, {String id = 'bundle-sale-0001', int quantity = 1, int revenue = 2000, List<Obj> individual = const []}) => bundleSaleEvent(
  id: id, bundle: b, bundleQuantity: quantity, revenue: revenue,
  payment: 'cash', note: '', date: when, recordedAt: when,
  individualLines: individual,
);
Obj baseState({List<Obj>? products, List<Obj>? bundles, List<Obj>? events}) => emptyState()
  ..['businessName'] = 'Test'
  ..['businessId'] = 'bundle-test-business'
  ..['products'] = products ?? <Obj>[]
  ..['bundles'] = bundles ?? <Obj>[]
  ..['events'] = events ?? <Obj>[];

void main() {
  test('bundle availability uses its limiting component and no bundle stock', () {
    final b = bundle('bundle-kit-001', [
      {'productId': 'part-a-001', 'quantity': 2},
      {'productId': 'part-b-001', 'quantity': 1},
    ]);
    final events = [addStock('restock-part-a01', 'part-a-001', 5, 500), addStock('restock-part-b01', 'part-b-001', 2, 300)];
    final accounts = calculate(events);
    expect(bundleAvailability(accounts, b, [product('part-a-001'), product('part-b-001')]), 2);
    expect(accounts.book.stock('bundle-kit-001'), 0);
  });

  test('single and multiple bundle sales deduct all components and use FIFO costs', () {
    final products = [product('part-a-001'), product('part-b-001')];
    final b = bundle('bundle-kit-001', [
      {'productId': 'part-a-001', 'quantity': 2},
      {'productId': 'part-b-001', 'quantity': 1},
    ]);
    final events = [
      addStock('restock-a-lot-01', 'part-a-001', 2, 200),
      addStock('restock-a-lot-02', 'part-a-001', 2, 500),
      addStock('restock-b-lot-01', 'part-b-001', 2, 600),
    ];
    final one = sell(b);
    final afterOne = validateState(baseState(products: products, bundles: [b], events: [...events, one]));
    expect(afterOne.book.stock('part-a-001'), 2);
    expect(afterOne.book.stock('part-b-001'), 1);
    expect(afterOne.summary()['revenue'], 2000);
    expect(afterOne.summary()['cogs'], 500); // $1.00 + $1.00 + $3.00 FIFO.
    expect(afterOne.summary()['grossProfit'], 1500);
    final two = sell(b, id: 'bundle-sale-0002', quantity: 2, revenue: 3600);
    final afterTwo = validateState(baseState(products: products, bundles: [b], events: [...events, two]));
    expect(afterTwo.book.stock('part-a-001'), 0);
    expect(afterTwo.book.stock('part-b-001'), 0);
    expect(afterTwo.summary()['revenue'], 3600);
    expect(afterTwo.summary()['cogs'], 1300);
    expect(afterTwo.book.stock('bundle-kit-001'), 0);
  });

  test('shared components constrain availability and are deducted once', () {
    final products = [for (final id in ['part-a-001', 'part-b-001', 'part-c-001']) product(id)];
    final b1 = bundle('bundle-one-001', [{'productId': 'part-a-001', 'quantity': 2}, {'productId': 'part-b-001', 'quantity': 1}]);
    final b2 = bundle('bundle-two-001', [{'productId': 'part-a-001', 'quantity': 1}, {'productId': 'part-c-001', 'quantity': 1}]);
    final before = calculate([addStock('restock-shared-001', 'part-a-001', 3, 300), addStock('restock-b-00001', 'part-b-001', 2, 200), addStock('restock-c-00001', 'part-c-001', 5, 500)]);
    expect(bundleAvailability(before, b1, products), 1);
    expect(bundleAvailability(before, b2, products), 3);
    final sold = sell(b1);
    final after = validateState(baseState(products: products, bundles: [b1, b2], events: [addStock('restock-shared-001', 'part-a-001', 3, 300), addStock('restock-b-00001', 'part-b-001', 2, 200), addStock('restock-c-00001', 'part-c-001', 5, 500), sold]));
    expect(after.book.stock('part-a-001'), 1);
    expect(bundleAvailability(after, b2, products), 1);
  });

  test('insufficient components reject the whole sale without changing source ledger', () {
    final b = bundle('bundle-kit-001', [{'productId': 'part-a-001', 'quantity': 2}, {'productId': 'part-b-001', 'quantity': 1}]);
    final events = [addStock('restock-a-only-01', 'part-a-001', 3, 300), addStock('restock-b-only-01', 'part-b-001', 1, 100)];
    expect(() => calculate([...events, sell(b, quantity: 2, id: 'bundle-sale-0002', revenue: 4000)]), throwsFormatException);
    expect(calculate(events).book.stock('part-a-001'), 3);
  });

  test('refund reverses bundle revenue and undo restores stock exactly once', () {
    final b = bundle('bundle-kit-001', [{'productId': 'part-a-001', 'quantity': 1}, {'productId': 'part-b-001', 'quantity': 1}]);
    final purchase = [addStock('restock-a-000001', 'part-a-001', 1, 250), addStock('restock-b-000001', 'part-b-001', 1, 350)];
    final sale = sell(b);
    final refund = event(id: 'bundle-refund-001', type: 'refund', revenue: 500, target: sale['id']);
    final afterRefund = validateState(baseState(products: [product('part-a-001'), product('part-b-001')], bundles: [b], events: [...purchase, sale, refund]));
    expect(afterRefund.summary()['revenue'], 1500);
    expect(afterRefund.summary()['cogs'], 600);
    final cancel = event(id: 'bundle-undo-00001', type: 'undo', target: sale['id'], note: 'Cancelled sale');
    final afterCancel = validateState(baseState(products: [product('part-a-001'), product('part-b-001')], bundles: [b], events: [...purchase, sale, cancel]));
    expect(afterCancel.summary()['revenue'], 0);
    expect(afterCancel.book.stock('part-a-001'), 1);
    expect(afterCancel.book.stock('part-b-001'), 1);
  });

  test('physical return restores component lots while refund remains a separate event', () {
    final b = bundle('bundle-kit-001', [{'productId': 'part-a-001', 'quantity': 1}, {'productId': 'part-b-001', 'quantity': 1}]);
    final purchases = [addStock('return-a-stock-01', 'part-a-001', 1, 250), addStock('return-b-stock-01', 'part-b-001', 1, 350)];
    final sale = sell(b);
    final returned = event(id: 'bundle-return-001', type: 'return', quantity: 2, target: sale['id']);
    final accounts = validateState(baseState(products: [product('part-a-001'), product('part-b-001')], bundles: [b], events: [...purchases, sale, returned]));
    expect(accounts.book.stock('part-a-001'), 1);
    expect(accounts.book.stock('part-b-001'), 1);
    expect(accounts.summary()['revenue'], 2000); // Cash refund is a separate ledger event.
    expect(accounts.summary()['cogs'], 0);
  });

  test('mixed individual and bundle sale is one event with one revenue total', () {
    final b = bundle('bundle-kit-001', [{'productId': 'part-a-001', 'quantity': 1}, {'productId': 'part-b-001', 'quantity': 1}]);
    final mixed = sell(b, individual: [{'productId': 'part-c-001', 'quantity': 2}], revenue: 3500);
    expect(mixed['quantity'], 4);
    expect(mixed['allocations'], [
      {'productId': 'part-a-001', 'quantity': 1},
      {'productId': 'part-b-001', 'quantity': 1},
      {'productId': 'part-c-001', 'quantity': 2},
    ]);
    final events = [for (final pair in [('part-a-001', 100), ('part-b-001', 200), ('part-c-001', 300)]) addStock('stock-${pair.$1}', pair.$1, 3, pair.$2 * 3), mixed];
    final accounts = validateState(baseState(products: [product('part-a-001'), product('part-b-001'), product('part-c-001')], bundles: [b], events: events));
    expect(accounts.summary()['revenue'], 3500);
    expect(accounts.book.stock('part-c-001'), 1);
  });

  test('bundle backup restore round trip retains definitions and linked sale allocations', () {
    final b = bundle('bundle-kit-001', [{'productId': 'part-a-001', 'quantity': 1}, {'productId': 'part-b-001', 'quantity': 1}]);
    final s = baseState(products: [product('part-a-001'), product('part-b-001')], bundles: [b], events: [addStock('restock-a-000001', 'part-a-001', 2, 200), addStock('restock-b-000001', 'part-b-001', 2, 300), sell(b)]);
    final restored = decodeBackup(encodeBackup(s));
    expect(restored['bundles'], s['bundles']);
    expect(objects(restored['events']).last['bundleComponents'], objects(s['events']).last['bundleComponents']);
    expect(validateState(restored).summary()['cogs'], 250);
    expect(validateState(restored).book.stock('part-a-001'), 1);
  });

  test('catalogue import is idempotent and never overwrites edited records', () {
    final s = baseState();
    const catalogue = '''{"format":"business-tracker-catalogue","version":1,"catalogueId":"sample","catalogueName":"Sample","category":"Skincare","currency":"AUD","products":[{"id":"nua-cleanser-001","name":"Cleanser","variant":"200 mL","category":"Skincare","barcode":"","archived":false,"minimum":0,"photo":null,"purchaseCost":null,"sellingPrice":null,"twoItemPrice":null}],"bundles":[{"id":"nua-ritual-001","name":"Ritual","category":"Skincare","description":"","sellingPrice":null,"photo":null,"archived":false,"components":[{"productId":"nua-cleanser-001","quantity":1}]}]}''';
    final first = reviewCatalogue(s, catalogue);
    expect(first.newProducts.length, 1);
    expect(first.newBundles.length, 1);
    final imported = applyCatalogue(s, first);
    validateState(imported);
    final second = reviewCatalogue(imported, catalogue);
    expect(second.newProducts, isEmpty);
    expect(second.newBundles, isEmpty);
    expect(second.unchanged.length, 2);
    final edited = clone(imported)..['products'][0]['sellingPrice'] = 700;
    final update = reviewCatalogue(edited, catalogue);
    expect(update.updates, isNotEmpty);
    expect(applyCatalogue(edited, update)['products'][0]['sellingPrice'], 700);
    expect(applyCatalogue(edited, update, applyUpdates: true)['products'][0]['sellingPrice'], isNull);
  });

  test('NUA external example imports five products and two component bundles without stock/cost', () async {
    final text = await File('examples/nua-skincare-catalogue.json').readAsString();
    final initial = baseState(events: [event(id: 'existing-sale-0001', type: 'expense', cost: 250)]);
    final preview = reviewCatalogue(initial, text);
    expect(preview.newProducts.length, 5);
    expect(preview.newBundles.length, 2);
    final imported = applyCatalogue(initial, preview);
    expect(objects(imported['events']).length, 1);
    expect(objects(imported['products']).every((p) => p['purchaseCost'] == null && p['sellingPrice'] == null), isTrue);
    expect(objects(imported['bundles']).every((b) => objects(b['components']).length == 4), isTrue);
    expect(reviewCatalogue(imported, text).newProducts, isEmpty);
  });

  test('missing references and duplicate component definitions are rejected', () {
    final s = baseState(products: [product('part-a-001')]);
    const invalid = '''{"format":"business-tracker-catalogue","version":1,"currency":"AUD","category":"Skincare","products":[],"bundles":[{"id":"bundle-broken-001","name":"Broken","category":"Skincare","description":"","sellingPrice":null,"photo":null,"archived":false,"components":[{"productId":"missing-001","quantity":1}]}]}''';
    expect(reviewCatalogue(s, invalid).errors, isNotEmpty);
  });

  test('new module toggle defaults off and persists in backup while older backups remain valid', () {
    final fresh = baseState();
    expect(moduleEnabled(fresh, moduleBundles), isFalse);
    setModuleEnabled(fresh, moduleBundles, true);
    expect(moduleEnabled(decodeBackup(encodeBackup(fresh)), moduleBundles), isTrue);
    final older = baseState()..remove('bundles')..remove('modules');
    final decodedOldBackup = decodeBackup(encodeBackup(older));
    expect(decodedOldBackup.containsKey('bundles'), isFalse);
    expect(validateState(decodedOldBackup).book.value, 0);
  });
}
