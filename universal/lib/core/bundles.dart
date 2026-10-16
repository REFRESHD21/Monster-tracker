import 'dart:convert';

import 'codec.dart';
import 'engine.dart';

List<Obj> bundleRecords(Obj state) => objects(state['bundles'] ?? const <dynamic>[]);

Obj? bundleById(Obj state, String id) =>
    bundleRecords(state).where((b) => b['id'] == id).firstOrNull;

int bundleAvailability(Accounts accounts, Obj bundle, [List<Obj>? products]) {
  if (bundle['archived'] == true) return 0;
  final components = objects(bundle['components']);
  if (components.isEmpty) return 0;
  var available = 0x7fffffff;
  for (final component in components) {
    if (products != null) {
      final product = products.where((p) => p['id'] == component['productId']).firstOrNull;
      if (product == null || product['archived'] == true) return 0;
    }
    final quantity = integer(component['quantity'], 1, 10000);
    final stock = accounts.book.stock(component['productId'] as String);
    final count = stock ~/ quantity;
    if (count < available) available = count;
  }
  return available;
}

int? bundleFifoCost(Accounts accounts, Obj bundle) {
  var total = 0;
  for (final component in objects(bundle['components'])) {
    final id = component['productId'] as String;
    final needed = integer(component['quantity'], 1, 10000);
    final lots = accounts.book.lots.values
        .where((lot) => lot.product == id && lot.quantity > 0)
        .toList()
      ..sort((a, b) => a.age.compareTo(b.age));
    var left = needed;
    for (final lot in lots) {
      if (left == 0) break;
      final take = left < lot.quantity ? left : lot.quantity;
      if (lot.cost == 0) return null;
      total += take == lot.quantity ? lot.cost : lot.cost * take ~/ lot.quantity;
      left -= take;
    }
    if (left > 0) throw const FormatException('Bundle components are out of stock.');
  }
  return total;
}

/// Creates one append-only sale event. Allocations contain the physical
/// component units so the existing FIFO engine consumes real product lots.
Obj bundleSaleEvent({
  required String id,
  required Obj bundle,
  required int bundleQuantity,
  required int revenue,
  required String payment,
  required String note,
  required int date,
  required int recordedAt,
  List<Obj> individualLines = const <Obj>[],
  String? customerId,
  int fee = 0,
  int outputGst = 0,
}) {
  integer(bundleQuantity, 1, 10000);
  integer(revenue, 0);
  final components = objects(bundle['components']);
  if (components.isEmpty) throw const FormatException('Bundle needs at least one product.');
  final totals = <String, int>{};
  for (final component in components) {
    final productId = string(component['productId'], 100);
    final quantity = integer(component['quantity'], 1, 10000) * bundleQuantity;
    totals[productId] = (totals[productId] ?? 0) + quantity;
  }
  final standalone = <String, int>{};
  for (final line in individualLines) {
    final productId = string(line['productId'], 100);
    final quantity = integer(line['quantity'], 1, 10000);
    standalone[productId] = (standalone[productId] ?? 0) + quantity;
    totals[productId] = (totals[productId] ?? 0) + quantity;
  }
  final allocations = totals.entries
      .map((entry) => {'productId': entry.key, 'quantity': entry.value})
      .toList();
  final physicalQuantity = allocations.fold<int>(0, (sum, row) => sum + row['quantity'] as int);
  return <String, dynamic>{
    'id': id,
    'type': 'sale',
    'quantity': physicalQuantity,
    'revenue': revenue,
    'fee': fee,
    'cost': 0,
    'payment': payment,
    'note': note,
    'target': null,
    'date': date,
    'recordedAt': recordedAt,
    'inputGst': 0,
    'outputGst': outputGst,
    'allocations': allocations,
    'bundleId': bundle['id'],
    'bundleName': bundle['name'],
    'bundleQuantity': bundleQuantity,
    'bundleComponents': components
        .map((component) => <String, dynamic>{
              'productId': component['productId'],
              'quantity': component['quantity'],
            })
        .toList(),
    'standaloneAllocations': standalone.entries.map((entry) => {'productId': entry.key, 'quantity': entry.value}).toList(),
    'productName': bundle['name'],
    if (customerId != null) 'customerId': customerId,
  };
}

class CatalogueReview {
  final List<Obj> newProducts;
  final List<Obj> newBundles;
  final List<String> unchanged;
  final List<String> conflicts;
  final List<String> errors;
  const CatalogueReview({
    required this.newProducts,
    required this.newBundles,
    required this.unchanged,
    required this.conflicts,
    required this.errors,
  });
  bool get canImport => errors.isEmpty && conflicts.isEmpty;
}

CatalogueReview reviewCatalogue(Obj state, String text) {
  final root = obj(strictJson(text));
  if (root['format'] != 'business-tracker-catalogue' ||
      root['version'] != 1 ||
      root['currency'] != 'AUD') {
    throw const FormatException('Unsupported catalogue format or currency.');
  }
  final errors = <String>[], conflicts = <String>[], unchanged = <String>[];
  final newProducts = <Obj>[], newBundles = <Obj>[];
  final productIds = <String>{}, bundleIds = <String>{};
  final existingProducts = {for (final p in objects(state['products'])) p['id'] as String: p};
  final existingBundles = {for (final b in bundleRecords(state)) b['id'] as String: b};
  final products = objects(root['products']);
  final bundles = objects(root['bundles']);
  if (products.length > 10000 || bundles.length > 10000) {
    throw const FormatException('Catalogue exceeds the record limit.');
  }
  for (final p in products) {
    try {
      final id = string(p['id'], 100), name = string(p['name'], 120).trim();
      if (id.isEmpty || name.isEmpty || !productIds.add(id)) throw const FormatException('Invalid or duplicate product ID/name.');
      string(p['category'], 80);
      string(p['variant'], 120);
      if (p['barcode'] != '' || p['archived'] is! bool || p['minimum'] != 0 || p['purchaseCost'] != null || p['sellingPrice'] != null || p['twoItemPrice'] != null) {
        throw const FormatException('Catalogue products must have empty barcodes, zero minimum and unknown prices/costs.');
      }
      if (p['photo'] != null) verifyAttachment(obj(p['photo']));
      final old = existingProducts[id];
      if (old == null) {
        newProducts.add(p);
      } else if (canonical(old) == canonical(p)) {
        unchanged.add('Product $name already exists.');
      } else {
        conflicts.add('Product ID $id already exists with different data; it will not be overwritten.');
      }
    } on Object catch (e) {
      errors.add('Product: $e');
    }
  }
  final allProducts = {...existingProducts.keys, ...newProducts.map((p) => p['id'] as String)};
  for (final b in bundles) {
    try {
      final id = string(b['id'], 100), name = string(b['name'], 120).trim();
      if (id.isEmpty || name.isEmpty || !bundleIds.add(id) || existingProducts.containsKey(id) || productIds.contains(id)) throw const FormatException('Invalid, duplicate or colliding bundle ID/name.');
      string(b['category'], 80);
      if (b['description'] is! String || b['sellingPrice'] != null || b['archived'] is! bool) throw const FormatException('Bundle must have no preset price and a valid archive state.');
      if (b['photo'] != null) {verifyAttachment(obj(b['photo']));if(b['photo']['mime']=='application/pdf')throw const FormatException('Bundle photos must be JPG or PNG images.');}
      final components = objects(b['components']);
      if (components.isEmpty) throw const FormatException('Bundle needs at least one component.');
      final seen = <String>{};
      for (final component in components) {
        final productId = string(component['productId'], 100);
        if (!allProducts.contains(productId)) throw FormatException('Bundle $name references missing product $productId.');
        if (!seen.add(productId)) throw FormatException('Bundle $name repeats product $productId; combine its quantity.');
        integer(component['quantity'], 1, 10000);
      }
      final old = existingBundles[id];
      if (old == null) {
        newBundles.add(b);
      } else if (canonical(old) == canonical(b)) {
        unchanged.add('Bundle $name already exists.');
      } else {
        conflicts.add('Bundle ID $id already exists with different data; it will not be overwritten.');
      }
    } on Object catch (e) {
      errors.add('Bundle: $e');
    }
  }
  return CatalogueReview(newProducts: newProducts, newBundles: newBundles, unchanged: unchanged, conflicts: conflicts, errors: errors);
}

Obj applyCatalogue(Obj state, CatalogueReview review) {
  if (!review.canImport) throw const FormatException('Resolve catalogue conflicts or errors before importing.');
  final next = clone(state);
  (next['products'] as List).addAll(review.newProducts.map(clone));
  final bundles=(next['bundles'] ??= <dynamic>[]) as List;
  bundles.addAll(review.newBundles.map(clone));
  return next;
}

String exportCatalogue(Obj state) => const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'format': 'business-tracker-catalogue',
      'version': 1,
      'catalogueId': 'custom-catalogue',
      'catalogueName': 'Business Tracker catalogue',
      'category': 'Products',
      'currency': 'AUD',
      'products': objects(state['products']).map((p) => <String, dynamic>{
        'id': p['id'], 'name': p['name'], 'variant': p['variant'],
        'category': p['category'], 'barcode': '', 'archived': p['archived'] == true,
        'minimum': 0, 'photo': p['photo'], 'purchaseCost': null,
        'sellingPrice': null, 'twoItemPrice': null,
      }).toList(),
      'bundles': bundleRecords(state).map((b) => <String, dynamic>{
        'id': b['id'], 'name': b['name'], 'category': b['category'],
        'description': b['description'] ?? '', 'sellingPrice': null,
        'photo': b['photo'], 'archived': b['archived'] == true,
        'components': objects(b['components']).map((c) => {'productId': c['productId'], 'quantity': c['quantity']}).toList(),
      }).toList(),
    });
