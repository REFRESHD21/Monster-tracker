import 'package:uuid/uuid.dart';
import 'codec.dart';
import 'engine.dart';
import 'products.dart';

List<Obj> stocktakeSessions(Obj state) => objects(state['stocktakes'] ?? const <dynamic>[]);

Obj startStocktake(Obj state, {String? id, int? at}) {
  final next = clone(state);
  final sessions = (next['stocktakes'] ??= <dynamic>[]) as List;
  final sessionId = id ?? const Uuid().v4();
  if (stocktakeSessions(next).any((s) => s['id'] == sessionId)) {
    throw const FormatException('This stocktake session already exists.');
  }
  final accounts = validateState(state);
  sessions.add({
    'id': sessionId,
    'status': 'counting',
    'startedAt': at ?? DateTime.now().toUtc().millisecondsSinceEpoch,
    'snapshotProducts': [
      for (final p in activeProducts(state))
        {'productId': p['id'], 'name': p['name'], 'variant': p['variant'] ?? '', 'expectedAtStart': accounts.book.stock(p['id'])},
    ],
    'counts': <dynamic>[],
    'adjustmentEventIds': <dynamic>[],
  });
  validateState(next);
  return next;
}

Obj recordStocktakeCount(Obj state, String sessionId, String productId, {
  required int sellable,
  required int damaged,
  int? eventCount,
  int? countedAt,
}) {
  integer(sellable, 0, 10000);
  integer(damaged, 0, 10000);
  final next = clone(state);
  final session = stocktakeSessions(next).where((s) => s['id'] == sessionId).firstOrNull;
  if (session == null || session['status'] != 'counting') throw const FormatException('This stocktake is not open for counts.');
  if (!objects(session['snapshotProducts']).any((p) => p['productId'] == productId)) throw const FormatException('This product is not part of the stocktake snapshot.');
  final events = objects(state['events']);
  final countThrough = eventCount ?? events.length;
  if (countThrough < 0 || countThrough > events.length) throw const FormatException('The stock snapshot is no longer available. Recount this product.');
  final expected = calculate(events.take(countThrough).toList()).book.stock(productId);
  final counts = objects(session['counts']);
  counts.removeWhere((c) => c['productId'] == productId);
  counts.add({
    'productId': productId,
    'eventCount': countThrough,
    'expectedSellable': expected,
    'sellable': sellable,
    'damaged': damaged,
    'countedAt': countedAt ?? DateTime.now().toUtc().millisecondsSinceEpoch,
  });
  session['counts'] = counts;
  validateState(next);
  return next;
}

List<Obj> stocktakePreview(Obj state, String sessionId) {
  final session = stocktakeSessions(state).where((s) => s['id'] == sessionId).firstOrNull;
  if (session == null) throw const FormatException('Stocktake session not found.');
  final events = objects(state['events']), current = validateState(state).book;
  final counts = {for (final c in objects(session['counts'])) c['productId'] as String: c};
  return [
    for (final p in objects(session['snapshotProducts']))
      (() {
        final id = p['productId'] as String, c = counts[id];
        if (c == null) return {'productId': id, 'name': p['name'], 'variant': p['variant'], 'counted': false};
        final expected = c['expectedSellable'] as int;
        final prefixStock = calculate(events.take(c['eventCount'] as int).toList()).book.stock(id);
        if (prefixStock != expected) throw const FormatException('Stock history changed under this count. Recount this product.');
        final sellable = c['sellable'] as int, damaged = c['damaged'] as int;
        final variance = sellable + damaged - expected;
        final now = current.stock(id);
        final projected = now + variance - damaged;
        return {
          'productId': id, 'name': p['name'], 'variant': p['variant'], 'counted': true,
          'expected': expected, 'current': now, 'sellable': sellable, 'damaged': damaged,
          'variance': variance, 'projected': projected, 'conflict': projected < 0,
        };
      })(),
  ];
}

/// Append idempotent stocktake adjustments to the existing stock ledger.
/// The count is reconciled against inventory at the moment that product was
/// counted, so later sales and receipts remain in the ledger and are retained.
Obj confirmStocktake(Obj state, String sessionId, {int? at, String Function()? newEventId}) {
  final next = clone(state);
  final session = stocktakeSessions(next).where((s) => s['id'] == sessionId).firstOrNull;
  if (session == null) throw const FormatException('Stocktake session not found.');
  if (session['status'] == 'completed') return next;
  final preview = stocktakePreview(state, sessionId);
  if (preview.any((p) => p['counted'] != true)) throw const FormatException('Count every product in the starting snapshot before confirming.');
  if (preview.any((p) => p['conflict'] == true)) throw const FormatException('Newer sales or stock movements leave less stock than this count requires. Recount the affected product before confirming.');
  final events = next['events'] as List;
  final generated = <String>[];
  final now = at ?? DateTime.now().toUtc().millisecondsSinceEpoch;
  String eventId() => newEventId?.call() ?? const Uuid().v4();
  for (final row in preview) {
    final id = row['productId'] as String, variance = row['variance'] as int, damaged = row['damaged'] as int;
    if (variance > 0) {
      final e = event(id: eventId(), type: 'stocktake_found', quantity: variance, productId: id, note: 'Stocktake ${sessionId.substring(0, sessionId.length < 8 ? sessionId.length : 8)} · found stock with unknown acquisition cost', date: now)
        ..['stocktakeSessionId'] = sessionId;
      events.add(e); generated.add(e['id'] as String);
    } else if (variance < 0) {
      final e = event(id: eventId(), type: 'missing', quantity: -variance, productId: id, note: 'Stocktake ${sessionId.substring(0, sessionId.length < 8 ? sessionId.length : 8)} · unaccounted stock', date: now)
        ..['stocktakeSessionId'] = sessionId;
      events.add(e); generated.add(e['id'] as String);
    }
    if (damaged > 0) {
      final e = event(id: eventId(), type: 'damaged', quantity: damaged, productId: id, note: 'Stocktake ${sessionId.substring(0, sessionId.length < 8 ? sessionId.length : 8)} · physically counted damaged stock', date: now)
        ..['stocktakeSessionId'] = sessionId;
      events.add(e); generated.add(e['id'] as String);
    }
  }
  session['status'] = 'completed';
  session['completedAt'] = now;
  session['adjustmentEventIds'] = generated;
  validateState(next);
  return next;
}

