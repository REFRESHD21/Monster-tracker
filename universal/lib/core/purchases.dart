import 'codec.dart';

const standardPackSizes = [4, 9, 12, 24];

/// A completed stock acquisition is represented by immutable restock ledger
/// events. The shared purchase metadata groups its independently costed lines;
/// replaying those events creates the FIFO lots used by sales and reporting.
List<Obj> createPurchaseEvents({
  required String purchaseId,
  required String supplier,
  required String location,
  required String reference,
  required String note,
  required int? date,
  required List<Obj> lines,
  required String Function() newEventId,
  int? recordedAt,
}) {
  if (purchaseId.trim().isEmpty || purchaseId.length > 100) {
    throw const FormatException('Purchase ID is required.');
  }
  if (supplier.trim().isEmpty || supplier.length > 120 ||
      location.length > 120 || reference.length > 120 || note.length > 500) {
    throw const FormatException('Check supplier, location, reference and notes.');
  }
  if (date != null) integer(date, 946684800000, 4102444800000);
  if (lines.isEmpty || lines.length > 100) {
    throw const FormatException('Add at least one purchase line.');
  }
  final batch = <String, dynamic>{
    'id': purchaseId,
    'supplier': supplier.trim(),
    'location': location.trim(),
    'reference': reference.trim(),
    'note': note.trim(),
    'date': date,
  };
  final ids = <String>{};
  return [
    for (final line in lines)
      (() {
        final productId = string(line['productId'], 100);
        final packSize = integer(line['packSize'], 1, 10000);
        final packCount = integer(line['packCount'], 1, 10000);
        final quantity = packSize * packCount;
        if (quantity > 10000) {
          throw const FormatException('A purchase line cannot exceed 10,000 cans.');
        }
        final gross = integer(line['grossCost'] ?? line['cost'], 0, 10000000);
        final discount = integer(line['discount'] ?? 0, 0, gross);
        final acquisition = integer(line['additionalCost'] ?? 0, 0, 10000000);
        final cost = gross - discount + acquisition;
        if (cost > 10000000) {
          throw const FormatException('Recorded acquisition cost exceeds the supported amount.');
        }
        final gst = integer(line['inputGst'] ?? 0, 0, cost);
        final lineId = string(line['lineId'], 100);
        final eventId = newEventId();
        if (lineId.isEmpty || !ids.add(lineId) || eventId.isEmpty) {
          throw const FormatException('Purchase line IDs must be unique.');
        }
        final now = recordedAt ?? DateTime.now().millisecondsSinceEpoch;
        return {
          'id': eventId,
          'type': 'restock',
          'quantity': quantity,
          'revenue': 0,
          'fee': 0,
          'cost': cost,
          'payment': 'none',
          'note': 'Purchase ${batch['supplier']}${batch['reference'].isEmpty ? '' : ' · ${batch['reference']}'}',
          'target': null,
          'date': date,
          'recordedAt': now,
          'inputGst': gst,
          'outputGst': 0,
          'allocations': [{'productId': productId, 'quantity': quantity}],
          'purchaseBatch': batch,
          'purchaseLine': {
            'id': lineId,
            'packSize': packSize,
            'packCount': packCount,
            'grossCost': gross,
            'discount': discount,
            'additionalCost': acquisition,
            'cost': cost,
          },
        };
      })(),
  ];
}

/// Validates and returns grouped completed purchases from the append-only
/// ledger. Legacy restock events remain valid and are not invented as invoices.
List<Obj> purchaseHistory(Obj state) {
  final groups = <String, Obj>{};
  final products = {for (final p in objects(state['products'])) p['id'] as String};
  final lineIds = <String>{};
  for (final event in objects(state['events'])) {
    if (event['purchaseBatch'] == null && event['purchaseLine'] == null) continue;
    final batch = obj(event['purchaseBatch']), line = obj(event['purchaseLine']);
    final id = string(batch['id'], 100);
    final allocations = objects(event['allocations']);
    if (event['type'] != 'restock' || id.isEmpty || allocations.length != 1 ||
        !products.contains(allocations.single['productId']) ||
        !lineIds.add(string(line['id'], 100)) ||
        integer(line['packSize'], 1, 10000) * integer(line['packCount'], 1, 10000) != event['quantity'] ||
        integer(line['cost']) != event['cost'] || line['id'] == '' ||
        integer(line['grossCost'] ?? line['cost']) - integer(line['discount'] ?? 0) + integer(line['additionalCost'] ?? 0) != event['cost'] ||
        batch['supplier'] is! String || (batch['supplier'] as String).trim().isEmpty ||
        batch['location'] is! String || batch['reference'] is! String || batch['note'] is! String ||
        batch['date'] != event['date']) {
      throw const FormatException('Invalid purchase-to-inventory link.');
    }
    final prior = groups[id];
    if (prior != null && canonical(prior['batch']) != canonical(batch)) {
      throw const FormatException('Purchase lines have conflicting shared details.');
    }
    final group = groups.putIfAbsent(id, () => {'batch': clone(batch), 'lines': <Obj>[]});
    (group['lines'] as List<Obj>).add({
      'eventId': event['id'],
      'productId': allocations.single['productId'],
      'quantity': event['quantity'],
      'packSize': line['packSize'],
      'packCount': line['packCount'],
      'grossCost': line['grossCost'] ?? line['cost'],
      'discount': line['discount'] ?? 0,
      'additionalCost': line['additionalCost'] ?? 0,
      'cost': line['cost'],
      'date': event['date'],
    });
  }
  return groups.values.toList()
    ..sort((a, b) => ((obj(b['batch'])['date'] as int?) ?? 0)
        .compareTo((obj(a['batch'])['date'] as int?) ?? 0));
}
