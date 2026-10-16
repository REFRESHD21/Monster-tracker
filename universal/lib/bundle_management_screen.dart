import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'core/bundles.dart';
import 'services/backups.dart';
import 'core/codec.dart';
import 'core/engine.dart';
import 'core/products.dart';

class BundleManagementScreen extends StatefulWidget {
  final Obj initialState;
  final Future<void> Function(Obj) onSave;
  final Future<Obj?> Function() pickPhoto;
  const BundleManagementScreen({super.key, required this.initialState, required this.onSave, required this.pickPhoto});
  @override State<BundleManagementScreen> createState() => _BundleManagementScreenState();
}

class _ComponentDraft {
  String productId;
  final TextEditingController quantity;
  _ComponentDraft(this.productId, [int count = 1]) : quantity = TextEditingController(text: '$count');
  void dispose() => quantity.dispose();
}

class _BundleManagementScreenState extends State<BundleManagementScreen> {
  late Obj state = clone(widget.initialState);
  bool busy = false;
  List<Obj> get products => activeProducts(state);
  List<Obj> get allProducts => objects(state['products']);
  Accounts get accounts => validateState(state);

  Future<void> importCatalogue() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
    if (picked == null) return;
    final file = picked.files.single;
    final bytes = file.bytes ?? await File(file.path!).readAsBytes();
    late CatalogueReview review;
    try { review = reviewCatalogue(state, utf8.decode(bytes)); } catch (e) { if (mounted) await showDialog<void>(context: context, builder: (c) => AlertDialog(title: const Text('Catalogue could not be read'), content: Text('$e'), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))])); return; }
    if (!mounted) return;
    var applyUpdates=false;
    final yes = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder:(c,update)=>AlertDialog(
      title: const Text('Review catalogue import'),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('${review.newProducts.length} new products · ${review.newBundles.length} new bundles · ${review.updates.length} updates · ${review.unchanged.length} unchanged'),
        if(review.updates.isNotEmpty)CheckboxListTile(contentPadding:EdgeInsets.zero,value:applyUpdates,onChanged:(v)=>update(()=>applyUpdates=v??false),title:const Text('Apply listed product and bundle changes'),subtitle:const Text('Historical ledger entries and stock are never changed.'),controlAffinity:ListTileControlAffinity.leading),
        for(final item in review.updates)Text(item),
        if (review.conflicts.isNotEmpty) ...[const Text('Conflicts:'), for (final error in review.conflicts) Text(error)],
        if (review.errors.isNotEmpty) ...[const Text('Errors:'), for (final error in review.errors) Text(error)],
        const Text('Catalogue import adds definitions only. It does not add stock, purchases, sales or costs.'),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), if (review.canImport && (review.newProducts.isNotEmpty || review.newBundles.isNotEmpty || applyUpdates)) FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(applyUpdates?'Import additions and confirmed updates':'Import additions'))],
    )));
    if (yes == true && mounted) await persist(applyCatalogue(state, review,applyUpdates:applyUpdates));
  }

  Future<void> exportCatalogueFile() async {
    await Backups.export('business-tracker-catalogue.json', utf8.encode(exportCatalogue(state)));
  }

  Future<void> persist(Obj next) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.onSave(next);
      if (mounted) setState(() => state = clone(next));
    } catch (e) {
      if (mounted) await showDialog<void>(context: context, builder: (c) => AlertDialog(title: const Text('Bundle not saved'), content: Text('$e'), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))]));
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> editBundle({Obj? existing, bool duplicate = false}) async {
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one individual product first.')));
      return;
    }
    final name = TextEditingController(text: duplicate ? '${existing?['name'] ?? ''} copy' : existing?['name'] as String? ?? '');
    final category = TextEditingController(text: existing?['category'] as String? ?? products.first['category'] as String? ?? '');
    final description = TextEditingController(text: existing?['description'] as String? ?? '');
    final price = TextEditingController(text: existing?['sellingPrice'] is int ? amount(existing!['sellingPrice'] as int) : '');
    Obj? photo = existing?['photo'] == null ? null : obj(existing!['photo']);
    final parts = <_ComponentDraft>[
      for (final c in objects(existing?['components'] ?? const <dynamic>[])) _ComponentDraft(c['productId'] as String, c['quantity'] as int),
    ];
    if (parts.isEmpty) parts.add(_ComponentDraft(products.first['id'] as String));
    final result = await showDialog<Obj>(context: context, builder: (d) => StatefulBuilder(builder: (d, update) => AlertDialog(
      title: Text(existing == null ? 'Create bundle' : duplicate ? 'Duplicate bundle' : 'Edit bundle'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Bundle name')),
        TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')),
        TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'Description (optional)')),
        TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Selling price (AUD)')),
        Text('Components · available ${_availability(existing)} bundles · FIFO component cost ${_cost(existing)}', style: Theme.of(context).textTheme.bodySmall),
        for (var i = 0; i < parts.length; i++) Row(children: [
          Expanded(child: DropdownButtonFormField<String>(value: allProducts.any((p) => p['id'] == parts[i].productId) ? parts[i].productId : products.first['id'] as String, decoration: InputDecoration(labelText: 'Product ${i + 1}'), items: [for (final p in allProducts) DropdownMenuItem(value: p['id'] as String, child: Text('${p['archived'] == true ? 'Archived · ' : ''}${productLabel(p)}'))], onChanged: (v) => update(() => parts[i].productId = v!))),
          const SizedBox(width: 8), SizedBox(width: 82, child: TextField(controller: parts[i].quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qty'))),
          IconButton(tooltip: 'Remove component', onPressed: parts.length == 1 ? null : () => update(() { parts.removeAt(i).dispose(); }), icon: const Icon(Icons.remove_circle_outline)),
        ]),
        TextButton.icon(onPressed: () => update(() => parts.add(_ComponentDraft(products.first['id'] as String))), icon: const Icon(Icons.add), label: const Text('Add component')),
        OutlinedButton.icon(onPressed: () async { final selected = await widget.pickPhoto(); if (selected != null) update(() => photo = selected); }, icon: const Icon(Icons.photo_outlined), label: Text(photo == null ? 'Add photo (optional)' : 'Replace photo')),
        if (photo != null) TextButton(onPressed: () => update(() => photo = null), child: const Text('Remove photo')),
        const Text('Bundle stock is calculated from its components. No separate bundle inventory is created.'),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () {
        try {
          if (name.text.trim().isEmpty) throw const FormatException('Enter a bundle name.');
          final componentRows = <Obj>[];
          final seen = <String>{};
          for (final part in parts) {
            final q = integer(int.tryParse(part.quantity.text), 1, 10000);
            if (!seen.add(part.productId)) throw const FormatException('Choose each product once; increase its quantity instead.');
            componentRows.add({'productId': part.productId, 'quantity': q});
          }
          final next = <String, dynamic>{
            'id': existing != null && !duplicate ? existing['id'] : const Uuid().v4(),
            'name': name.text.trim(), 'category': category.text.trim(), 'description': description.text.trim(),
            'sellingPrice': price.text.trim().isEmpty ? null : cents(price.text),
            'components': componentRows, 'archived': false, 'photo': photo,
          };
          Navigator.pop(d, next);
        } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
      }, child: const Text('Save bundle'))],
    )));
    for (final part in parts) { part.dispose(); }
    name.dispose(); category.dispose(); description.dispose(); price.dispose();
    if (result == null || !mounted) return;
    final next = clone(state);
    final existingIndex = objects(next['bundles'] ?? const <dynamic>[]).indexWhere((b) => b['id'] == result['id']);
    if (existingIndex >= 0) (next['bundles'] as List)[existingIndex] = result;
    else { final list = (next['bundles'] ??= <dynamic>[]) as List; list.add(result); }
    await persist(next);
  }

  int _availability(Obj? b) => b == null ? 0 : bundleAvailability(accounts, b, objects(state['products']));
  String _cost(Obj? b) { if (b == null) return '—'; try { final cost=bundleFifoCost(accounts, b); return cost==null?'Cost unknown':money(cost); } catch (_) { return 'Unavailable'; } }

  @override Widget build(BuildContext context) {
    final bundles = bundleRecords(state);
    return Scaffold(appBar: AppBar(title: const Text('Bundles & Combos')), body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Build bundles from existing products. Inventory remains on component products; bundle sales use their FIFO lots.'),
      if (busy) const LinearProgressIndicator(),
      OutlinedButton.icon(onPressed: busy ? null : () => editBundle(), icon: const Icon(Icons.add), label: const Text('Create Bundle')),
      OutlinedButton.icon(onPressed: busy ? null : importCatalogue, icon: const Icon(Icons.file_open_outlined), label: const Text('Import catalogue JSON')),
      OutlinedButton.icon(onPressed: busy ? null : exportCatalogueFile, icon: const Icon(Icons.download_outlined), label: const Text('Export catalogue JSON')),
      if (bundles.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('No bundles yet.')),
      for (final bundle in bundles) Card(child: ListTile(
        title: Text('${bundle['name']}${bundle['archived'] == true ? ' · Archived' : ''}'),
        subtitle: Text('${bundle['category']} · ${bundle['sellingPrice'] is int ? money(bundle['sellingPrice'] as int) : 'Set a selling price'}\n${objects(bundle['components']).map((c) => '${c['quantity']} × ${productLabel(products.firstWhere((p) => p['id'] == c['productId'], orElse: () => {'name': 'Archived / missing product', 'variant': ''}))}').join('\n')}\nAvailable ${_availability(bundle)} · FIFO cost ${_cost(bundle)}'),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(onSelected: (value) async {
          if (value == 'edit') await editBundle(existing: bundle);
          if (value == 'duplicate') await editBundle(existing: bundle, duplicate: true);
          if (value == 'archive') { final next = clone(state); objects(next['bundles']).firstWhere((b) => b['id'] == bundle['id'])['archived'] = true; await persist(next); }
          if (value == 'restore') { final next = clone(state); objects(next['bundles']).firstWhere((b) => b['id'] == bundle['id'])['archived'] = false; await persist(next); }
        }, itemBuilder: (_) => [
          if (bundle['archived'] != true) const PopupMenuItem(value: 'edit', child: Text('Edit')),
          if (bundle['archived'] != true) const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
          if (bundle['archived'] != true) const PopupMenuItem(value: 'archive', child: Text('Archive')),
          if (bundle['archived'] == true) const PopupMenuItem(value: 'restore', child: Text('Restore')),
        ]),
      )),
    ]));
  }
}
