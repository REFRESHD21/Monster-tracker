import 'package:flutter_test/flutter_test.dart';
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';

void main() {
  test('reproduces Reports crash when profit is unknown', () {
    const product = <String, dynamic>{
      'id': 'drink-1',
      'name': 'Test drink',
      'variant': '',
      'sellingPrice': 350,
      'archived': false,
    };
    final accounts = calculate([
      event(
        id: 'restock-0001',
        type: 'restock',
        quantity: 1,
        productId: 'drink-1',
        cost: 0,
      ),
      event(
        id: 'sale-000001',
        type: 'sale',
        quantity: 1,
        productId: 'drink-1',
        revenue: 350,
        payment: 'cash',
      ),
    ]);

    final report = accounts.salesProfit([product]);
    final rows = report['products'] as List;
    final profit = rows.single['profit'];

    // Unknown purchase cost is intentionally represented as null, not zero.
    expect(profit, isNull);

    // This is the exact unsafe formatter call made by the Reports product row.
    expect(() => money(profit), throwsA(isA<TypeError>()));
  });
}
