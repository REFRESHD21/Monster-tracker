import 'codec.dart';
import 'engine.dart';

bool isArchived(Obj product) => product['archived'] == true;
List<Obj> activeProducts(Obj state) => objects(state['products']).where((p) => !isArchived(p)).toList();
String productLabel(Obj p) => '${p['name']}${p['variant'] == '' ? '' : ' · ${p['variant']}'}';

/// Explicit deal selection only. A custom quantity of two uses the normal price.
int saleTotal(Obj product, int quantity, {bool deal = false}) {
  if (isArchived(product)) throw const FormatException('Restore this archived product before selling it.');
  integer(quantity, 1, 10000);
  if (deal) {
    if (quantity != 2 || product['twoItemPrice'] == null) throw const FormatException('No two-item deal is configured for this product.');
    return integer(product['twoItemPrice'], 1);
  }
  return integer(integer(product['sellingPrice']) * quantity);
}

bool referencesProduct(dynamic value, String id) {
  if (value is Map) return value.values.any((v) => referencesProduct(v, id));
  if (value is List) return value.any((v) => referencesProduct(v, id));
  return value == id;
}

class ProductRemoval {
  final int stock, pending;
  final bool history, references;
  ProductRemoval(this.stock, this.pending, this.history, this.references);
  bool get canArchive => stock == 0 && pending == 0;
  bool get canDelete => canArchive && !history && !references;
  String get explanation => [
    if (stock != 0) '$stock units remain. Sell, transfer, or record missing/damaged stock before removal.',
    if (pending != 0) '$pending pending transaction(s) or refund(s) must be resolved first. Imported pending refunds must be resolved with the original provider; this app does not process payments.',
    if (history || references) 'History or other references exist. Archive hides this product from active lists and sale pickers; its name, transactions and reports are retained.',
    if (canDelete) 'No stock, history or other references exist. This product can be permanently deleted.',
  ].join('\n\n');
}

ProductRemoval productRemoval(Obj state, String id) {
  final events = objects(state['events']);
  final history = events.any((e) => referencesProduct(e, id));
  final others = {...state}..remove('products')..remove('events');
  var pending = events.where((e) => referencesProduct(e, id) && (e['reservedRefund'] as int? ?? 0) > 0).length;
  for (final key in ['pendingTransactions', 'pendingSales', 'checkout']) {
    final value = state[key];
    if (value != null && referencesProduct(value, id)) pending++;
  }
  return ProductRemoval(validateState(state).book.stock(id), pending, history, referencesProduct(others, id));
}

/// Enforced at the repository boundary too, not just by disabled UI controls.
void validateProductChanges(Obj before, Obj after, {bool restoring=false}) {
  final current = objects(before['products']), next = objects(after['products']);
  for (final p in current) {
    final replacement = next.where((n) => n['id'] == p['id']).firstOrNull;
    if (replacement == null && !productRemoval(before, p['id']).canDelete) {
      throw const FormatException('Product has stock, history or references. Resolve stock and pending items, then archive it instead.');
    }
    if (!restoring && replacement != null && !isArchived(p) && isArchived(replacement) && !productRemoval(before, p['id']).canArchive) {
      throw const FormatException('Resolve remaining stock and pending transactions before archiving.');
    }
  }
  if(restoring)return;
  final oldIds = objects(before['events']).map((e) => e['id']).toSet();
  for (final e in objects(after['events']).where((e) => !oldIds.contains(e['id']) && ['sale','single','deal','restock','transfer'].contains(e['type']))) {
    for (final p in next.where(isArchived)) {
      if (referencesProduct(e, p['id'])) throw const FormatException('Restore the archived product before recording new sales or stock.');
    }
  }
}
