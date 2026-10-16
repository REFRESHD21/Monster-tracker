import 'codec.dart';

const moduleCustomerAccounts = 'customerAccounts';
const modulePriceComparison = 'storePriceComparison';
const moduleForecasting = 'salesForecasting';
const moduleSmartRestock = 'budgetSmartRestock';

const moduleKeys = <String>[
  moduleCustomerAccounts,
  modulePriceComparison,
  moduleForecasting,
  moduleSmartRestock,
];

const moduleNames = <String, String>{
  moduleCustomerAccounts: 'Customer Accounts & IOUs',
  modulePriceComparison: 'Store Price Comparison',
  moduleForecasting: 'Sales Forecasting',
  moduleSmartRestock: 'Budget-Aware Smart Restocking',
};

Obj moduleFlags(Obj state) {
  final stored = state['modules'];
  return <String, dynamic>{
    for (final key in moduleKeys)
      key: stored is Map<String, dynamic> && stored[key] == true,
  };
}

bool moduleEnabled(Obj state, String key) => moduleFlags(state)[key] == true;

void setModuleEnabled(Obj state, String key, bool enabled) {
  if (!moduleKeys.contains(key)) throw const FormatException('Unknown business module.');
  state['modules'] = <String, dynamic>{...moduleFlags(state), key: enabled};
}

List<Obj> customerRecords(Obj state) => objects(state['customers'] ?? const <dynamic>[]);
List<Obj> customerPaymentRecords(Obj state) => objects(state['customerPayments'] ?? const <dynamic>[]);
List<Obj> retailerOfferRecords(Obj state) => objects(state['retailerOffers'] ?? const <dynamic>[]);

Map<String, int> customerBalances(Obj state) {
  final sales = <String, int>{};
  final linked = <String, Set<String>>{};
  final undone = objects(state['events'] ?? const <dynamic>[])
      .where((e) => e['type'] == 'undo')
      .map((e) => e['target'] as String?)
      .whereType<String>()
      .toSet();
  for (final event in objects(state['events'] ?? const <dynamic>[])) {
    if (!['sale', 'single', 'deal'].contains(event['type']) ||
        event['payment'] != 'iou' ||
        event['customerId'] is! String ||
        undone.contains(event['id'])) continue;
    final customerId = event['customerId'] as String;
    sales[customerId] = (sales[customerId] ?? 0) + integer(event['revenue']);
    (linked[customerId] ??= <String>{}).add(event['id'] as String);
  }
  for (final event in objects(state['events'] ?? const <dynamic>[])) {
    if (event['type'] != 'refund' || event['target'] is! String) continue;
    for (final customerId in linked.keys) {
      if (linked[customerId]!.contains(event['target'])) {
        sales[customerId] = (sales[customerId] ?? 0) - integer(event['revenue']);
        break;
      }
    }
  }
  for (final payment in customerPaymentRecords(state)) {
    final customerId = payment['customerId'] as String;
    sales[customerId] = (sales[customerId] ?? 0) - integer(payment['amount'], 1);
  }
  return sales;
}

List<Obj> offersForProduct(Obj state, String productId) {
  final offers = retailerOfferRecords(state)
      .where((offer) => offer['productId'] == productId)
      .map((offer) => <String, dynamic>{
            ...offer,
            'unitCost': (integer(offer['priceCents'], 1) +
                    integer(offer['packQuantity'], 1) -
                    1) ~/
                integer(offer['packQuantity'], 1),
          })
      .toList();
  offers.sort((a, b) {
    final cost = (a['unitCost'] as int).compareTo(b['unitCost'] as int);
    if (cost != 0) return cost;
    final date = (b['observedAt'] as int).compareTo(a['observedAt'] as int);
    return date != 0 ? date : (a['retailer'] as String).compareTo(b['retailer'] as String);
  });
  return offers;
}

/// Uses the latest 30 days of actual completed unit sales. With fewer than
/// three sales or seven days of observable history, no numeric forecast is
/// returned. It does not infer demand during stockouts.
Obj salesForecast(Obj state, {required int horizonDays, required int now}) {
  if (![7, 30, 90].contains(horizonDays)) throw const FormatException('Unsupported forecast period.');
  const dayMs = 86400000;
  final windowStart = now - 30 * dayMs;
  final events = objects(state['events'] ?? const <dynamic>[]);
  final saleEvents = events.where((e) =>
      ['sale', 'single', 'deal'].contains(e['type']) &&
      e['date'] is int &&
      (e['date'] as int) >= windowStart &&
      (e['date'] as int) <= now &&
      !events.any((undo) => undo['type'] == 'undo' && undo['target'] == e['id'])).toList();
  final saleIds = saleEvents.map((e) => e['id'] as String).toSet();
  final refunds = <String, int>{}, returns = <String, int>{};
  for (final event in events) {
    final target = event['target'];
    if (!saleIds.contains(target)) continue;
    if (event['type'] == 'refund') refunds[target as String] = (refunds[target] ?? 0) + integer(event['revenue']);
    if (event['type'] == 'return') returns[target as String] = (returns[target] ?? 0) + integer(event['quantity']);
  }
  final counts=<String,int>{}, revenues=<String,int>{}, saleDays=<int>{};
  for(final sale in saleEvents) {
    final saleId=sale['id'] as String, date=sale['date'] as int;
    saleDays.add(date~/dayMs);
    final quantity=integer(sale['quantity'],1), refund=(refunds[saleId]??0).clamp(0,integer(sale['revenue']));
    final netRevenue=integer(sale['revenue'])-refund;
    var returnLeft=(returns[saleId]??0).clamp(0,quantity), before=0, revenueDistributed=0;
    final allocations=objects(sale['allocations']);
    for(var i=0;i<allocations.length;i++) {
      final allocation=allocations[i], q=integer(allocation['quantity'],1);
      final returned=returnLeft<q?returnLeft:q;returnLeft-=returned;
      final kept=q-returned;
      final productId=allocation['productId'] as String;
      final revenuePart=i==allocations.length-1?netRevenue-revenueDistributed:netRevenue*(before+q)~/quantity-netRevenue*before~/quantity;
      revenueDistributed+=revenuePart;before+=q;
      counts[productId]=(counts[productId]??0)+kept;
      revenues[productId]=(revenues[productId]??0)+revenuePart;
    }
  }
  final daysSorted=saleDays.toList()..sort();
  final spanDays=daysSorted.isEmpty?0:daysSorted.last-daysSorted.first+1;
  final observedDays=daysSorted.isEmpty?0:((now-windowStart)~/dayMs).clamp(1,30);
  final enough=saleEvents.length>=3 && spanDays>=7 && observedDays>=7;
  final products=<Obj>[];
  for(final product in objects(state['products']??const <dynamic>[])) {
    final id=product['id'] as String, units=counts[id]??0, revenue=revenues[id]??0;
    final forecastUnits=enough?(units*horizonDays+observedDays~/2)~/observedDays:null;
    final forecastRevenue=enough?(revenue*horizonDays+observedDays~/2)~/observedDays:null;
    products.add(<String,dynamic>{'productId':id,'name':product['name'],'observedUnits':units,'observedRevenue':revenue,'forecastUnits':forecastUnits,'forecastRevenue':forecastRevenue});
  }
  return <String,dynamic>{
    'horizonDays':horizonDays,'lookbackDays':30,'observedDays':observedDays,
    'saleCount':saleEvents.length,'saleSpanDays':spanDays,'limited':!enough,
    'uncertainty':'Stockout days are not modeled; estimates use recorded sales from the last 30 days.',
    'products':products,
  };
}
/// Tops each active product up only to its configured minimum. It allocates a
/// user-entered budget by low-stock severity and never places an order.
List<Obj> budgetRestockPlan(
  List<Obj> products,
  Map<String, int> stockByProduct,
  List<Obj> offers, {
  required int budgetCents,
}) {
  integer(budgetCents);
  final needs = <Obj>[];
  for (final product in products.where((p) => p['archived'] != true)) {
    final id = product['id'] as String;
    final stock = integer(stockByProduct[id] ?? 0);
    final minimum = integer(product['minimum']);
    final need = minimum > stock ? minimum - stock : 0;
    if (need == 0) continue;
    final productOffers = offersForProduct({'retailerOffers': offers}, id);
    final unitCost = productOffers.isNotEmpty
        ? integer(productOffers.first['unitCost'])
        : integer(product['purchaseCost']);
    needs.add(<String, dynamic>{
      'productId': id,
      'name': product['name'],
      'stock': stock,
      'minimum': minimum,
      'needed': need,
      'unitCost': unitCost,
      'costSource': productOffers.isNotEmpty ? 'manual retailer offer' : 'recorded purchase cost',
      'urgency': minimum == 0 ? 1.0 : stock / minimum,
    });
  }
  needs.sort((a, b) {
    final urgency = (a['urgency'] as double).compareTo(b['urgency'] as double);
    return urgency != 0 ? urgency : (a['name'] as String).compareTo(b['name'] as String);
  });
  var remaining = budgetCents;
  return needs.map((need) {
    final unitCost = need['unitCost'] as int;
    final affordable = unitCost == 0 ? need['needed'] as int : remaining ~/ unitCost;
    final planned = (need['needed'] as int) < affordable ? need['needed'] as int : affordable;
    final cost = planned * unitCost;
    remaining -= cost;
    return <String, dynamic>{
      ...need,
      'planned': planned,
      'estimatedCost': cost,
      'budgetLimited': planned < (need['needed'] as int),
    };
  }).toList();
}
