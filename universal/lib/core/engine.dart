import 'dart:convert';
import 'codec.dart';
import 'purchases.dart';
import 'business_modules.dart';

const legacyProduct = 'legacy-unassigned';
const themes = ['light', 'dark', 'green', 'ocean', 'purple', 'warm neutral'];
Obj emptyState() => {'format': 'business-tracker', 'version': 1, 'currency': 'AUD', 'timeZone': 'Australia/Perth', 'businessId': '', 'businessName': 'My business', 'theme': 'green', 'products': <dynamic>[], 'events': <dynamic>[], 'attachments': <dynamic>[], 'moneyEntries': <dynamic>[], 'stocktakes': <dynamic>[], 'modules': <String,dynamic>{}, 'customers': <dynamic>[], 'customerPayments': <dynamic>[], 'retailerOffers': <dynamic>[], 'bundles': <dynamic>[], 'legacy': null, 'legacyCount': 0};
class Lot {
  final String key, product; final int age; int quantity, cost;
  Lot(this.key, this.product, this.age, this.quantity, this.cost);
  Lot copy([int? q, int? c]) => Lot(key, product, age, q ?? quantity, c ?? cost);
}
class Book {
  final Map<String, Lot> lots = {}; int age = 0;
  void add(Lot p) { final l = lots.putIfAbsent(p.key, () => Lot(p.key, p.product, p.age, 0, 0)); l.quantity += p.quantity; l.cost += p.cost; }
  List<Lot> take(String product, int q, [String? preferred]) {
    final available = lots.values.where((l) => l.product == product && l.quantity > 0).toList()
      ..sort((a, b) { final p = (a.key == preferred ? 0 : 1).compareTo(b.key == preferred ? 0 : 1); return p == 0 ? a.age.compareTo(b.age) : p; });
    final out = <Lot>[];
    for (final l in available) { final n = q < l.quantity ? q : l.quantity; if (n == 0) break; final c = n == l.quantity ? l.cost : l.cost * n ~/ l.quantity; out.add(l.copy(n, c)); l.quantity -= n; l.cost -= c; q -= n; }
    if (q != 0) throw const FormatException('Not enough stock. No changes saved.');
    return out;
  }
  int get value => lots.values.fold(0, (s, l) => s + l.cost);
  int stock(String product) => lots.values.where((l) => l.product == product).fold(0, (s, l) => s + l.quantity);
}
const sums = ['revenue','cash','card','iou','fees','purchases','expenses','cogs','losses','outputGst','inputGst'];
Obj row(Obj e, String? p, [String? kind]) => {'id': e['id'], 'kind': kind ?? e['type'], 'date': e['date'], 'productId': p, 'note': e['note'], for (final k in sums) k: 0};
int share(int total, int before, int q, int all) => total * (before + q) ~/ all - total * before ~/ all;
int costOf(List<Lot> lots) => lots.fold(0, (s, l) => s + l.cost);
class Action {
  final Obj e; final List<Lot> lots; final List<Obj> rows;
  Action(this.e, this.lots, this.rows);
}
class Accounts {
  final Book book; final List<Obj> rows; final Map<String, Action> history;
  Accounts(this.book, this.rows, this.history);
  Obj summary([int? from, int? to]) {
    final chosen = rows.where((r) => from == null || r['date'] != null && (r['date'] as int) >= from && (to == null || (r['date'] as int) < to));
    final r = <String, dynamic>{for(final k in sums) k: chosen.fold<int>(0, (s, e) => s + (e[k] as int))};
    r['grossProfit'] = r['revenue'] - r['outputGst'] - r['cogs'];
    r['netProfit'] = r['grossProfit'] - r['fees'] - r['expenses'] - r['losses'];
    r['inventoryValue'] = book.value; r['unknownDates'] = rows.where((r) => r['date'] == null).length;
    return r;
  }
  /// Sales-only performance and current-stock estimates, independent of
  /// operating expenses and damaged/missing stock write-offs.
  Obj salesProfit(List<Obj> products, [int? from, int? to]) {
    final chosen = rows.where((r) => from == null || r['date'] != null && (r['date'] as int) >= from && (to == null || (r['date'] as int) < to));
    final earned = <String, Obj>{};
    for (final p in products) {
      earned[p['id'] as String] = {'productId':p['id'],'name':p['name'],'variant':p['variant'] ?? '', 'unitsSold':0,'revenue':0,'cogs':0,'profit':0};
    }
    final productById={for(final p in products)p['id'] as String:p},unknownEarnedByProduct=<String,int>{},unknownBySale=<String,Map<String,int>>{};
    var revenue=0,cogs=0,units=0;
    for (final r in chosen) {
      if (!['single','deal','sale','refund','correction','goods_return'].contains(r['kind'])) continue;
      final p=earned[r['productId']]; if(p==null) continue;
      final e=history[r['id']]; final original=e?.e['type'];
      if (['single','deal','sale'].contains(original)) {final sale=e!;final sold=objects(sale.e['allocations']).where((a)=>a['productId']==r['productId']).fold<int>(0,(sum,a)=>sum+a['quantity'] as int);p['unitsSold']+=sold;units+=sold;
        for(final lot in sale.lots.where((lot)=>lot.product==r['productId']&&lot.cost==0)){
          final origin=history[lot.key.split('|').first];final originCost=origin?.lots.where((source)=>source.product==r['productId']).fold<int>(0,(sum,source)=>sum+source.cost) ?? 0;
          if(originCost==0){unknownEarnedByProduct[r['productId']]=(unknownEarnedByProduct[r['productId']]??0)+lot.quantity;(unknownBySale.putIfAbsent(sale.e['id'] as String,()=>{}))[r['productId']]=(unknownBySale[sale.e['id']]![r['productId']]??0)+lot.quantity;}
        }
      }
      else if(original=='return'){final returned=e!.lots.where((lot)=>lot.product==r['productId']).fold<int>(0,(sum,lot)=>sum+lot.quantity);p['unitsSold']-=returned;units-=returned;}
      else if(original=='undo'){final source=history[e!.e['target']];if(source!=null&&['single','deal','sale'].contains(source.e['type'])){final reversed=objects(source.e['allocations']).where((a)=>a['productId']==r['productId']).fold<int>(0,(sum,a)=>sum+a['quantity'] as int);p['unitsSold']-=reversed;units-=reversed;final unknown=unknownBySale[source.e['id']]?[r['productId']]??0;if(unknown>0){final left=(unknownEarnedByProduct[r['productId']]??0)-unknown;if(left<=0)unknownEarnedByProduct.remove(r['productId']);else unknownEarnedByProduct[r['productId']]=left;}}else if(source?.e['type']=='return'){final returned=source!.lots.where((lot)=>lot.product==r['productId']).fold<int>(0,(sum,lot)=>sum+lot.quantity);p['unitsSold']+=returned;units+=returned;}}
      p['revenue'] += r['revenue'] as int;
      // Returns carry negative COGS in the existing FIFO ledger, reversing
      // the original units' cost when those units return to sellable stock.
      p['cogs'] += r['cogs'] as int;
    }
    for(final p in earned.values){p['profit']=(unknownEarnedByProduct[p['productId']]??0)>0?null:p['revenue']-p['cogs'];revenue+=p['revenue'] as int;cogs+=p['cogs'] as int;}
    final potential=<String,Obj>{};var futureRevenue=0,futureCost=0,unknownCosts=0,unknownPrices=0;
    for(final entry in earned.entries){
      final p=productById[entry.key]!, archived=p['archived']==true, stock=archived?0:book.stock(entry.key), price=(p['sellingPrice'] as int? ?? 0), remainingCost=archived?0:book.lots.values.where((l)=>l.product==entry.key).fold<int>(0,(sum,l)=>sum+l.cost);
      final unitsWithCost=book.lots.values.where((l)=>l.product==entry.key && l.quantity>0 && l.cost>0).fold<int>(0,(sum,l)=>sum+l.quantity);
      if(stock>unitsWithCost) unknownCosts += stock-unitsWithCost;
      if(price<=0 && stock>0)unknownPrices+=stock;
      final estimate=price*stock;futureRevenue+=estimate;futureCost+=remainingCost;
      potential[entry.key]={'productId':entry.key,'name':p['name'],'variant':p['variant']??'','unitsSold':entry.value['unitsSold'],'revenue':entry.value['revenue'],'cogs':entry.value['cogs'],'profit':entry.value['profit'],'remaining':stock,'futureRevenue':stock>0&&price<=0?null:estimate,'futureCost':remainingCost,'futureProfit':stock>unitsWithCost||stock>0&&price<=0?null:estimate-remainingCost};
    }
    final knownFutureRevenue=unknownPrices==0?futureRevenue:null,knownFutureProfit=unknownPrices==0&&unknownCosts==0?futureRevenue-futureCost:null,knownEarnedProfit=unknownEarnedByProduct.isEmpty?revenue-cogs:null;
    return {'revenue':revenue,'cogs':cogs,'profit':knownEarnedProfit,'unitsSold':units,'futureRevenue':knownFutureRevenue,'futureCost':futureCost,'futureProfit':knownFutureProfit,'totalRevenue':knownFutureRevenue==null?null:revenue+knownFutureRevenue,'totalProfit':knownEarnedProfit==null||knownFutureProfit==null?null:knownEarnedProfit+knownFutureProfit,'unknownDates':rows.where((r)=>r['date']==null).length,'unknownCostUnits':unknownCosts,'unknownEarnedCostUnits':unknownEarnedByProduct.values.fold<int>(0,(sum,q)=>sum+q),'unknownPriceUnits':unknownPrices,'products':potential.values.toList()};
  }
}
Accounts calculate(List<Obj> events) {
  final book = Book(), history = <String, Action>{}, rows = <Obj>[];
  final undone = <String>{}, returned = <String, int>{}, refunded = <String, int>{};
  for (final e in events) {
    final id = string(e['id'], 100), type = string(e['type']);
    if (!RegExp(r'^[A-Za-z0-9-]{10,100}$').hasMatch(id) || history.containsKey(id)) throw const FormatException('Duplicate or invalid transaction ID.');
    if(e['date']!=null)integer(e['date'],946684800000,4102444800000);integer(e['recordedAt'],946684800000,4102444800000);string(e['note']);
    final q = integer(e['quantity'], 0, 10000);
    for (final k in ['revenue','fee','cost','inputGst','outputGst']) { integer(e[k]); }
    final int revenue = e['revenue'], fee = e['fee'], cost = e['cost'], input = e['inputGst'], output = e['outputGst'];
    if (input > cost || output > revenue) throw const FormatException('Invalid tax snapshot.');
    final parts = <Lot>[], er = <Obj>[];
    if (type == 'undo') {
      if(q!=0 || revenue!=0 || fee!=0 || cost!=0 || input!=0 || output!=0 || e['payment']!='none' || objects(e['allocations']).isNotEmpty)throw const FormatException('Invalid correction fields.');
      final source = history[e['target']];
      if (source == null || undone.contains(e['target']) || ['undo','transfer','refund_observation'].contains(source.e['type']) || (refunded[e['target']] ?? 0) != 0 || (returned[e['target']] ?? 0) != 0 || string(e['note']).trim().isEmpty) throw const FormatException('This record cannot be corrected. Check refunds and returns.');
      if (source.e['type'] == 'restock') {
        for (final p in source.lots) { parts.addAll(book.take(p.product, p.quantity, p.key)); }
      } else if (source.e['type'] == 'return') {
        for (final p in source.lots) { parts.addAll(book.take(p.product, p.quantity, p.key)); }
        returned[source.e['target']] = (returned[source.e['target']] ?? 0) - (source.e['quantity'] as int);
      } else { for (final p in source.lots) { book.add(p); } }
      int before = 0;
      for (final r in source.rows) {
        final next = row(e, r['productId'] as String?, 'correction'); for (final k in sums) { next[k] = -(r[k] as int); }
        if (['restock','return'].contains(source.e['type'])) {
          final n = source.lots.where((p) => p.product == r['productId']).fold<int>(0, (s, p) => s + p.quantity);
          next['losses'] += share(costOf(parts) - costOf(source.lots), before, n, source.e['quantity'] as int); before += n;
        }
        if(source.e['type']=='refund'){final sale=history[source.e['target']]!,active=refunded[source.e['target']] ?? 0;final amount=source.e['revenue'] as int;final gst=(sale.e['outputGst'] as int)*active~/(sale.e['revenue'] as int)-(sale.e['outputGst'] as int)*(active-amount)~/(sale.e['revenue'] as int);final n=objects(sale.e['allocations']).firstWhere((a)=>a['productId']==r['productId'])['quantity'] as int;next['outputGst']=share(gst,before,n,sale.e['quantity'] as int);before+=n;}
        er.add(next);
      }
      if(source.e['type']=='refund') refunded[source.e['target']] = (refunded[source.e['target']] ?? 0) - (source.e['revenue'] as int);
      undone.add(e['target'] as String);
    } else if (type == 'transfer') {
      if(q < 1 || revenue!=0 || cost!=0 || fee!=0 || input!=0 || output!=0 || e['from'] == e['to']) throw const FormatException('Invalid transfer.');
      for (final p in book.take(e['from'] as String, q)) { book.add(Lot('${p.key.split('|').first}|${e['to']}', e['to'] as String, p.age, p.quantity, p.cost)); }
    } else if (type == 'refund' || type == 'refund_observation') {
      final sale = history[e['target']];
      if (sale == null || !['single','deal','sale'].contains(sale.e['type']) || undone.contains(e['target'])) throw const FormatException('Refund needs an active original sale.');
      final before = refunded[e['target']] ?? 0;
      final int delta = type == 'refund' ? revenue : integer(e['delta'],-10000000,10000000);
      if(type=='refund' && (revenue<1 || cost!=0 || q!=0 || input!=0 || output!=0))throw const FormatException('Invalid refund entry.');
      final after = before + delta;
      if (after < 0 || after + (type=='refund'?(sale.e['reservedRefund'] as int? ?? 0):0) > sale.e['revenue'] || sale.e['revenue'] == 0) throw const FormatException('Refund exceeds original sale.');
      refunded[e['target']] = after;
      if(type == 'refund' && sale.e['payment']=='cash' && fee!=0) throw const FormatException('Cash refunds cannot have fees.');
      int accumulated = 0;
      final allocations = objects(sale.e['allocations']);
      final gstDelta = (sale.e['outputGst'] as int) * after ~/ (sale.e['revenue'] as int) - (sale.e['outputGst'] as int) * before ~/ (sale.e['revenue'] as int);
      for(final a in allocations) {
        final r = row(e, a['productId'] as String, 'refund'), n = a['quantity'] as int;
        r['revenue'] = -share(delta, accumulated, n, sale.e['quantity'] as int);
        r[sale.e['payment'] as String] = r['revenue'];
        final int feeDelta = type == 'refund' ? fee : integer(e['feeDelta'],-10000000,10000000);
        r['fees'] = share(feeDelta, accumulated, n, sale.e['quantity'] as int);
        r['outputGst'] = -share(gstDelta, accumulated, n, sale.e['quantity'] as int);
        er.add(r); accumulated += n;
      }
    } else if (type == 'return') {
      if(cost!=0 || revenue!=0 || fee!=0 || input!=0 || output!=0)throw const FormatException('Return does not record a new purchase or refund.');
      final source = history[e['target']];
      if (source == null || !['single','deal','sale'].contains(source.e['type']) || undone.contains(e['target']) || q < 1) throw const FormatException('Return needs an active original sale.');
      var skip = returned[e['target']] ?? 0, remaining = q;
      if (skip + q > source.e['quantity']) throw const FormatException('Returned quantity exceeds original sale.');
      returned[e['target']] = skip + q;
      for (final p in source.lots) {
        final within = skip < p.quantity ? skip : p.quantity; skip -= within;
        final n = remaining < p.quantity - within ? remaining : p.quantity - within;
        if (n > 0) { final c = p.cost * (within + n) ~/ p.quantity - p.cost * within ~/ p.quantity; final lot = p.copy(n, c); parts.add(lot); book.add(lot); final r = er.where((r)=>r['productId']==p.product).firstOrNull ?? row(e,p.product,'goods_return');if(!er.contains(r))er.add(r);r['cogs'] = (r['cogs'] as int)-c; remaining -= n; }
      }
      if(objects(e['allocations']).isNotEmpty){final actual=<String,int>{};for(final p in parts){actual[p.product]=(actual[p.product] ?? 0)+p.quantity;}for(final a in objects(e['allocations'])){if(actual.remove(a['productId'])!=a['quantity'])throw const FormatException('Returned product does not match original sale.');}if(actual.isNotEmpty)throw const FormatException('Incomplete return allocation.');}
    } else if (type == 'expense') {
      if(q!=0 || revenue!=0 || fee!=0 || output!=0 || e['payment']!='none')throw const FormatException('Invalid expense.');
      final r = row(e, null); r['expenses'] = cost - input; r['inputGst'] = input; er.add(r);
    } else if (['restock','single','deal','sale','missing','damaged','lost','stocktake_found'].contains(type)) {
      final allocations = objects(e['allocations']);
      if (q < 1 || allocations.isEmpty || allocations.fold<int>(0, (s,a) => s + integer(a['quantity'],1,10000)) != q || allocations.map((a)=>a['productId']).toSet().length != allocations.length) throw const FormatException('Invalid product quantities.');
      final sale = ['single','deal','sale'].contains(type);
      if(sale && (!['cash','card','iou'].contains(e['payment']) || cost != 0 || fee > revenue || e['payment'] == 'cash' && fee != 0 || e['payment'] == 'iou' && fee != 0)) throw const FormatException('Invalid payment or fee.');
      if(!sale && (revenue != 0 || fee != 0 || e['payment'] != 'none' || type != 'restock' && cost != 0)) throw const FormatException('Invalid stock adjustment.');
      int before = 0;
      for(final a in allocations) {
        final p = string(a['productId'], 100), n = a['quantity'] as int, r = row(e,p);
        final purchase = share(cost,before,n,q), credit = share(input,before,n,q);
        if(type == 'restock' || type == 'stocktake_found') { final lot = Lot('$id|$p',p,book.age++,n,purchase-credit); parts.add(lot);book.add(lot); }
        else { final used = book.take(p,n);parts.addAll(used);r[sale ? 'cogs' : 'losses'] = costOf(used); }
        r['revenue'] = share(revenue,before,n,q); if(sale) r[e['payment'] as String] = r['revenue'];
        r['fees'] = share(fee,before,n,q);r['purchases'] = purchase;r['inputGst'] = credit;r['outputGst'] = share(output,before,n,q);er.add(r);before += n;
      }
    } else { throw FormatException('Unsupported event: $type'); }
    rows.addAll(er); history[id] = Action(e, parts, er);
  }
  return Accounts(book, rows, history);
}
Obj event({required String id, required String type, int quantity = 0, String? productId, int revenue = 0, int fee = 0, int cost = 0, String payment = 'none', String note = '', String? target, int? date, int inputGst = 0, int outputGst = 0}) => {
  'id':id,'type':type,'quantity':quantity,'revenue':revenue,'fee':fee,'cost':cost,'payment':payment,'note':note,'target':target,'date':date ?? DateTime.now().millisecondsSinceEpoch,'recordedAt':DateTime.now().millisecondsSinceEpoch,'inputGst':inputGst,'outputGst':outputGst,'allocations':productId == null ? <dynamic>[] : [{'productId':productId,'quantity':quantity}],
};

void validateStocktakes(Obj state) {
  final sessions = objects(state['stocktakes'] ?? const <dynamic>[]), ids = <String>{};
  final ledger = objects(state['events']), events = {for (final e in ledger) e['id'] as String: e};
  final linkedEvents = <String>{};
  for (final e in ledger.where((e) => e['stocktakeSessionId'] != null)) {
    final sessionId = string(e['stocktakeSessionId'], 100);
    if (!linkedEvents.add(e['id'] as String) || !sessions.any((s) => s['id'] == sessionId)) throw const FormatException('Invalid stocktake adjustment link.');
    if (!['missing', 'damaged', 'stocktake_found'].contains(e['type'])) throw const FormatException('Unsupported stocktake adjustment type.');
  }
  for (final s in sessions) {
    final id = string(s['id'], 100), status = s['status'];
    integer(s['startedAt'], 946684800000, 4102444800000);
    if (id.isEmpty || !ids.add(id) || !['counting', 'completed'].contains(status)) throw const FormatException('Invalid stocktake session.');
    final productIds = <String>{};
    for (final p in objects(s['snapshotProducts'])) {
      final productId = string(p['productId'], 100);
      if (!productIds.add(productId) || !objects(state['products']).any((x) => x['id'] == productId)) throw const FormatException('Invalid stocktake product snapshot.');
      string(p['name'], 120); string(p['variant'], 120); integer(p['expectedAtStart'], 0, 10000000);
    }
    final counted = <String>{};
    for (final c in objects(s['counts'])) {
      final productId = string(c['productId'], 100), eventCount = integer(c['eventCount'], 0, ledger.length);
      if (!productIds.contains(productId) || !counted.add(productId)) throw const FormatException('Invalid stocktake count.');
      integer(c['expectedSellable'], 0, 10000); integer(c['sellable'], 0, 10000); integer(c['damaged'], 0, 10000);
      integer(c['countedAt'], 946684800000, 4102444800000);
      if (calculate(ledger.take(eventCount).toList()).book.stock(productId) != c['expectedSellable']) throw const FormatException('Stocktake count does not match its inventory snapshot.');
    }
    final adjustmentIds = (s['adjustmentEventIds'] as List).map((x) => string(x, 100)).toList();
    if (adjustmentIds.toSet().length != adjustmentIds.length) throw const FormatException('Duplicate stocktake adjustment reference.');
    if (status == 'completed') {
      integer(s['completedAt'], 946684800000, 4102444800000);
      if (counted.length != productIds.length || adjustmentIds.any((eventId) => events[eventId]?['stocktakeSessionId'] != id) || linkedEvents.where((eventId) => events[eventId]?['stocktakeSessionId'] == id).length != adjustmentIds.length) throw const FormatException('Incomplete stocktake history.');
    } else if (adjustmentIds.isNotEmpty || s.containsKey('completedAt')) {
      throw const FormatException('An open stocktake cannot contain applied adjustments.');
    }
  }
}

void validateStocktakeChanges(Obj before, Obj after) {
  final updated = {for (final s in objects(after['stocktakes'] ?? const <dynamic>[])) s['id'] as String: s};
  for (final prior in objects(before['stocktakes'] ?? const <dynamic>[])) {
    final current = updated[prior['id']];
    if (current == null) throw const FormatException('Stocktake history cannot be deleted.');
    if (prior['status'] == 'completed' && canonical(prior) != canonical(current)) throw const FormatException('Completed stocktake history cannot be edited.');
    if (prior['status'] == 'counting') {
      for (final key in ['id', 'startedAt', 'snapshotProducts']) {
        if (canonical(prior[key]) != canonical(current[key])) throw const FormatException('Stocktake identity and starting snapshot cannot be changed.');
      }
    }
  }
}

Accounts validateState(Obj s) {
  if(s['format'] != 'business-tracker' || s['version'] != 1 || s['currency'] != 'AUD' || s['timeZone'] != 'Australia/Perth' || !themes.contains(s['theme'])) throw const FormatException('Unsupported tracker backup.');
  if(string(s['businessName'],120).trim().isEmpty) throw const FormatException('Enter a business name.');
  if(s['lastPayment'] != null && !['cash','card'].contains(s['lastPayment'])) throw const FormatException('Invalid saved payment method.');
  if((s['events'] as List).length>100000 || (s['products'] as List).length>10000 || (s['attachments'] as List).length>100000)throw const FormatException('History limit reached. Export a full backup before adding more records.');
  final flags=s['modules'];
  if(flags!=null){if(flags is! Map<String,dynamic> || flags.keys.any((k)=>!moduleKeys.contains(k)) || flags.values.any((v)=>v is! bool))throw const FormatException('Invalid optional module settings.');}
  final products = <String>{}, barcodes = <String>{};
  for(final p in objects(s['products'])) {
    if(!products.add(string(p['id'],100)) || string(p['name'],120).trim().isEmpty) throw const FormatException('Invalid product identity.');
    for(final k in ['purchaseCost','sellingPrice']) {if(p[k]!=null)integer(p[k]);} integer(p['minimum']);
    if(p['twoItemPrice'] != null) integer(p['twoItemPrice'],1);
    if(p['archived'] != null && p['archived'] is! bool) throw const FormatException('Invalid product archive setting.');
    string(p['category'],80);string(p['variant'],120);
    final barcode=string(p['barcode'],80);if(barcode.isNotEmpty && !barcodes.add(barcode)) throw const FormatException('Barcode already belongs to another product.');
    if(p['photo'] != null){verifyAttachment(obj(p['photo']));if(p['photo']['mime']=='application/pdf')throw const FormatException('Product photos must be JPG or PNG images.');}
  }
  final moneyIds=<String>{};
  for(final entry in objects(s['moneyEntries'] ?? const <dynamic>[])){
    final id=string(entry['id'],100),type=string(entry['type'],30);
    if(id.isEmpty || !moneyIds.add(id) || !['add','remove','recount','sale','refund','correction','restock'].contains(type))throw const FormatException('Invalid business funds entry.');
    integer(entry['amount'],0,1000000000);integer(entry['delta'],-1000000000,1000000000);integer(entry['date'],946684800000,4102444800000);string(entry['note'] ?? '',240);
    if(type=='recount' && (entry['amount'] as int)<0)throw const FormatException('Invalid funds recount.');
    if(entry['saleId']!=null)string(entry['saleId'],100);
    if(entry['payment']!=null && !['cash','card','iou','none'].contains(entry['payment']))throw const FormatException('Invalid funds payment method.');
  }
  final customerIds=<String>{};
  for(final customer in objects(s['customers'] ?? const <dynamic>[])){final id=string(customer['id'],100);if(id.isEmpty || !customerIds.add(id) || string(customer['name'],120).trim().isEmpty)throw const FormatException('Invalid customer record.');if(customer['phone']!=null)string(customer['phone'],40);integer(customer['createdAt'],946684800000,4102444800000);}
  final paymentIds=<String>{};
  for(final payment in objects(s['customerPayments'] ?? const <dynamic>[])){final id=string(payment['id'],100);if(id.isEmpty || !paymentIds.add(id) || !customerIds.contains(payment['customerId']))throw const FormatException('Invalid customer payment record.');integer(payment['amount'],1);integer(payment['date'],946684800000,4102444800000);string(payment['note'] ?? '',240);}
  final offerIds=<String>{};
  for(final offer in objects(s['retailerOffers'] ?? const <dynamic>[])){final id=string(offer['id'],100);if(id.isEmpty || !offerIds.add(id) || !products.contains(offer['productId']) || offer['source']!='manual')throw const FormatException('Invalid store price offer.');string(offer['retailer'],120);string(offer['location'] ?? '',120);integer(offer['packQuantity'],1,10000);integer(offer['priceCents'],1);integer(offer['observedAt'],946684800000,4102444800000);}
  for(final e in objects(s['events'])) { for(final a in objects(e['allocations'])) {if(!products.contains(a['productId'])) throw const FormatException('Unknown product in history.');} if(e['type']=='transfer' && (!products.contains(e['from']) || !products.contains(e['to']))) throw const FormatException('Unknown transfer product.'); if(e['payment']=='iou' && (!['single','deal','sale'].contains(e['type']) || !customerIds.contains(e['customerId'])))throw const FormatException('IOU sales must reference a customer.');if(e['customerId']!=null && !customerIds.contains(e['customerId']))throw const FormatException('Sale references an unknown customer.'); }
  validateBundles(s);
  purchaseHistory(s);
  validateStocktakes(s);
  final ids=<String>{};for(final a in objects(s['attachments'])) {verifyAttachment(a,s);if(!ids.add(a['id'] as String)) throw const FormatException('Duplicate receipt.');}
  final result=calculate(objects(s['events']));for(final a in objects(s['attachments'])) {if(!result.history.containsKey(a['eventId'])) throw const FormatException('Receipt has no transaction.');}
  return result;
}
void validateBundles(Obj state) {
  final products={for(final p in objects(state['products'])) p['id'] as String:p};
  final ids=<String>{};
  for(final bundle in objects(state['bundles'] ?? const <dynamic>[])) {
    final id=string(bundle['id'],100),name=string(bundle['name'],120).trim();
    if(id.isEmpty || name.isEmpty || !ids.add(id) || products.containsKey(id)) throw const FormatException('Invalid, duplicate or colliding bundle.');
    string(bundle['category'],80);string(bundle['description'] ?? '',1000);
    if(bundle['sellingPrice']!=null)integer(bundle['sellingPrice'],1);
    if(bundle['archived']!=null && bundle['archived'] is! bool)throw const FormatException('Invalid bundle archive setting.');
    final seen=<String>{};final components=objects(bundle['components']);
    if(components.isEmpty)throw const FormatException('Bundle needs components.');
    for(final component in components) {final productId=string(component['productId'],100);if(!products.containsKey(productId) || !seen.add(productId))throw const FormatException('Bundle has an unknown or duplicate component.');integer(component['quantity'],1,10000);}
    if(bundle['photo']!=null){verifyAttachment(obj(bundle['photo']));if(bundle['photo']['mime']=='application/pdf')throw const FormatException('Bundle photos must be JPG or PNG images.');}
  }
  for(final event in objects(state['events'])) {
    if(event['bundleId']==null)continue;
    final bundleId=string(event['bundleId'],100),name=string(event['bundleName'],120);
    integer(event['bundleQuantity'],1,10000);
    final definition=objects(state['bundles'] ?? const <dynamic>[]).where((b)=>b['id']==bundleId).firstOrNull;
    if(definition==null || name.isEmpty || event['type']!='sale')throw const FormatException('Bundle sale references a missing bundle definition.');
    final parts=objects(event['bundleComponents']);if(parts.isEmpty)throw const FormatException('Bundle sale is missing its component snapshot.');
    final snapshot=<String,int>{};for(final part in parts){if(!products.containsKey(part['productId']))throw const FormatException('Bundle sale references an unknown component.');final productId=part['productId'] as String;if(snapshot.containsKey(productId))throw const FormatException('Bundle sale has duplicate component rows.');snapshot[productId]=integer(part['quantity'],1,10000)*integer(event['bundleQuantity'],1,10000);}
    for(final part in objects(event['standaloneAllocations'] ?? const <dynamic>[])){final productId=string(part['productId'],100);if(!products.containsKey(productId))throw const FormatException('Mixed sale references an unknown individual product.');snapshot[productId]=(snapshot[productId]??0)+integer(part['quantity'],1,10000);}
    final allocations=<String,int>{for(final allocation in objects(event['allocations'])) allocation['productId'] as String:allocation['quantity'] as int};
    if(canonical(snapshot)!=canonical(allocations))throw const FormatException('Bundle sale allocations do not match its component snapshot.');
  }
}

void verifyAttachment(Obj a,[Obj? state]) {
  final bytes = attachmentBytes(a,state);
  if(bytes.isEmpty || bytes.length > 16*1024*1024 || bytesHash(bytes) != a['sha256'] || attachmentMime(bytes)!=a['mime'] || !['image/jpeg','image/png','application/pdf'].contains(a['mime'])) throw const FormatException('Invalid or damaged attachment.');
}

List<int> attachmentBytes(Obj a,[Obj? state]) {
  if(a['data'] is String)return base64Decode(a['data'] as String);
  final index=integer(a['legacyIndex'],0,99),photos=objects(state?['legacy']?['receipts'] ?? []);
  if(index>=photos.length || photos[index]['id']!=a['id'] || photos[index]['eventId']!=a['eventId'])throw const FormatException('Invalid legacy receipt association.');
  return base64Decode(photos[index]['base64'] as String);
}

String attachmentMime(List<int> bytes) {
  if(bytes.length>=3 && bytes[0]==255 && bytes[1]==216 && bytes[2]==255)return 'image/jpeg';
  if(bytes.length>=8 && canonical(bytes.take(8).toList())=='[137,80,78,71,13,10,26,10]')return 'image/png';
  if(bytes.length>=5 && String.fromCharCodes(bytes.take(5))=='%PDF-')return 'application/pdf';
  throw const FormatException('Choose an original JPG, PNG or PDF.');
}

/// Half-open reporting ranges in the original fixed Perth business timezone.
(int?,int?) reportRange(String kind, DateTime instant) {
  if(kind=='all')return (null,null);
  final local=instant.toUtc().add(const Duration(hours:8));
  var start=DateTime.utc(local.year,local.month,local.day),end=start.add(const Duration(days:1));
  switch(kind){
    case 'day':break;
    case 'week':start=start.subtract(Duration(days:local.weekday-1));end=start.add(const Duration(days:7));
    case 'month':start=DateTime.utc(local.year,local.month);end=DateTime.utc(local.year,local.month+1);
    case 'quarter':final month=((local.month-1)~/3)*3+1;start=DateTime.utc(local.year,month);end=DateTime.utc(local.year,month+3);
    case 'year':start=DateTime.utc(local.year);end=DateTime.utc(local.year+1);
    case 'financial year':final year=local.month<7?local.year-1:local.year;start=DateTime.utc(year,7);end=DateTime.utc(year+1,7);
    default:throw const FormatException('Unknown report period.');
  }
  return (start.subtract(const Duration(hours:8)).millisecondsSinceEpoch,end.subtract(const Duration(hours:8)).millisecondsSinceEpoch);
}
