import 'package:flutter_test/flutter_test.dart';
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';
import 'package:business_tracker/core/legacy.dart';
import 'package:business_tracker/core/purchases.dart';

void main() {
  test('multi-product purchase records actual packs and separate FIFO costs', () {
    final state = emptyState();
    state['products'] = [
      product('drink-cola-001', 'Cola'),
      product('drink-mango-01', 'Mango'),
    ];
    var eventNumber=0;
    final purchase = createPurchaseEvents(
      purchaseId: 'purchase-group-0001',
      supplier: 'Spudshed',
      location: 'Balcatta',
      reference: 'R-123',
      note: 'Member discount included',
      date: 1780000000000,
      recordedAt: 1780000001000,
      newEventId: () => 'purchase-line-event-${eventNumber++}',
      lines: [
        {'lineId': 'purchase-line-cola-001', 'productId': 'drink-cola-001', 'packSize': 24, 'packCount': 2, 'grossCost': 4800, 'discount': 300, 'additionalCost': 400, 'inputGst': 436},
        {'lineId': 'purchase-line-mango-01', 'productId': 'drink-mango-01', 'packSize': 9, 'packCount': 1, 'cost': 2700},
      ],
    );
    state['events'] = purchase;

    final accounts = validateState(state);
    final history = purchaseHistory(state).single;
    expect(objects(history['lines']), hasLength(2));
    expect(accounts.book.stock('drink-cola-001'), 48);
    expect(accounts.book.stock('drink-mango-01'), 9);
    expect(accounts.book.value, 7164); // Discount, allocable cost and actual GST are reflected.
    expect(accounts.summary()['revenue'], 0);
    expect(accounts.summary()['purchases'], 7600);

    final backup = decodeBackup(encodeBackup(state));
    expect(validateState(backup).book.value, 7164);
    expect(objects(purchaseHistory(backup).single['lines']).first['discount'], 300);
    expect(purchaseHistory(backup).single['batch'], history['batch']);
  });

  test('purchase date may be unknown without inventing a timestamp', () {
    final events = createPurchaseEvents(
      purchaseId: 'purchase-unknown-001', supplier: 'Local shop', location: '',
      reference: '', note: '', date: null, recordedAt: 1780000000000,
      newEventId: () => 'purchase-unknown-event-01',
      lines: [{'lineId':'purchase-unknown-line-01','productId':'drink-cola-001','packSize':4,'packCount':1,'cost':800}],
    );
    final state = emptyState()..['products']=[product('drink-cola-001','Cola')]..['events']=events;
    expect(events.single['date'], isNull);
    expect(purchaseHistory(state).single['batch']['date'], isNull);
    expect(validateState(state).summary()['unknownDates'], 1);
  });

  test('invalid purchase lines and purchase-to-stock tampering are rejected', () {
    expect(() => createPurchaseEvents(
      purchaseId:'purchase-invalid-001',supplier:'Shop',location:'',reference:'',note:'',date:null,
      newEventId:()=> 'purchase-invalid-event-01',
      lines:[{'lineId':'purchase-invalid-line-01','productId':'drink-cola-001','packSize':24,'packCount':500,'cost':1}],
    ), throwsFormatException);
    final events = createPurchaseEvents(
      purchaseId:'purchase-valid-0001',supplier:'Shop',location:'',reference:'',note:'',date:null,
      newEventId:()=> 'purchase-valid-event-01',
      lines:[{'lineId':'purchase-valid-line-01','productId':'drink-cola-001','packSize':4,'packCount':1,'cost':800}],
    );
    final changed=clone(events.single)..['quantity']=3;
    final state=emptyState()..['products']=[product('drink-cola-001','Cola')]..['events']=[changed];
    expect(()=>validateState(state),throwsFormatException);
  });
}

Obj product(String id, String name) => {
  'id': id, 'name': name, 'category': 'Monster', 'variant': '500 ml',
  'purchaseCost': 100, 'sellingPrice': 350, 'minimum': 0, 'barcode': '', 'photo': null,
};
