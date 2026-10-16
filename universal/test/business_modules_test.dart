import 'package:flutter_test/flutter_test.dart';
import 'package:business_tracker/core/business_modules.dart';
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';

Obj product(String id,{int minimum=0,int cost=100,bool archived=false})=>{
  'id':id,'name':id,'category':'Drink','variant':'500 ml',
  'purchaseCost':cost,'sellingPrice':300,'minimum':minimum,'barcode':'','photo':null,
  if(archived)'archived':true,
};

void main() {
  test('module settings default off and switch independently through backup-safe state',(){
    final state=emptyState();
    expect(moduleKeys.every((key)=>!moduleEnabled(state,key)),isTrue);
    setModuleEnabled(state,moduleCustomerAccounts,true);
    expect(moduleEnabled(state,moduleCustomerAccounts),isTrue);
    expect(moduleKeys.where((key)=>key!=moduleCustomerAccounts).every((key)=>!moduleEnabled(state,key)),isTrue);
    setModuleEnabled(state,modulePriceComparison,true);
    setModuleEnabled(state,moduleCustomerAccounts,false);
    expect(moduleEnabled(state,moduleCustomerAccounts),isFalse);
    expect(moduleEnabled(state,modulePriceComparison),isTrue);
    expect(moduleEnabled(clone(state),modulePriceComparison),isTrue);
    expect(()=>setModuleEnabled(state,'unknown',true),throwsFormatException);
  });

  test('old backups without optional module data remain valid and off by default',(){
    final old=emptyState()
      ..remove('modules')
      ..remove('customers')
      ..remove('customerPayments')
      ..remove('retailerOffers');
    expect(validateState(old).summary()['revenue'],0);
    expect(moduleEnabled(old,moduleCustomerAccounts),isFalse);
    expect(customerBalances(old),isEmpty);
    expect(retailerOfferRecords(old),isEmpty);
  });

  test('customer IOU sales share sales revenue and later payments do not create sales',(){
    final state=emptyState();
    state['products']=[product('iou-product-0001',cost:208)];
    state['customers']=[{'id':'customer-00001','name':'Alex','phone':null,'createdAt':DateTime.now().millisecondsSinceEpoch}];
    state['events']=[
      event(id:'iou-restock-0001',type:'restock',quantity:2,productId:'iou-product-0001',cost:416),
      {...event(id:'iou-sale-00001',type:'sale',quantity:2,productId:'iou-product-0001',revenue:600,payment:'iou'),'customerId':'customer-00001'},
    ];
    var accounts=validateState(state);
    expect(accounts.summary()['revenue'],600);
    expect(accounts.summary()['iou'],600);
    expect(accounts.summary()['cash'],0);
    expect(accounts.summary()['card'],0);
    expect(customerBalances(state)['customer-00001'],600);
    state['customerPayments']=[{'id':'cust-payment-0001','customerId':'customer-00001','amount':200,'date':DateTime.now().millisecondsSinceEpoch,'note':''}];
    state['events'].add(event(id:'iou-refund-0001',type:'refund',target:'iou-sale-00001',revenue:100));
    accounts=validateState(state);
    expect(accounts.summary()['revenue'],500);
    expect(accounts.summary()['iou'],500);
    expect(customerBalances(state)['customer-00001'],300);
    expect(accounts.book.stock('iou-product-0001'),0);
    state['events'].add(event(
      id:'iou-undo-refund-0001',
      type:'undo',
      target:'iou-refund-0001',
      note:'Refund reversal correction',
    ));
    accounts=validateState(state);
    expect(accounts.summary()['revenue'],600);
    expect(customerBalances(state)['customer-00001'],400);
  });

  test('invalid IOU without an existing customer is rejected',(){
    final state=emptyState();
    state['products']=[product('iou-product-0001')];
    state['events']=[{...event(id:'iou-sale-00001',type:'sale',quantity:1,productId:'iou-product-0001',revenue:300,payment:'iou'),'customerId':'missing-customer'}];
    expect(()=>validateState(state),throwsFormatException);
  });

  test('store offers sort by exact product per-can price using integer cents',(){
    final state=emptyState()..['products']=[product('price-product-01'),product('price-product-02')];
    state['retailerOffers']=[
      {'id':'offer-woolies-001','productId':'price-product-01','retailer':'Woolworths','location':'Perth','packQuantity':4,'priceCents':281,'observedAt':10,'source':'manual'},
      {'id':'offer-coles-0001','productId':'price-product-01','retailer':'Coles','location':'Perth','packQuantity':4,'priceCents':280,'observedAt':11,'source':'manual'},
      {'id':'offer-other-0001','productId':'price-product-02','retailer':'IGA','location':'Perth','packQuantity':1,'priceCents':50,'observedAt':12,'source':'manual'},
    ];
    expect(offersForProduct(state,'price-product-01').map((o)=>o['retailer']),['Coles','Woolworths']);
    expect(offersForProduct(state,'price-product-01').first['unitCost'],70);
    expect(offersForProduct(state,'price-product-01').every((o)=>o['source']=='manual'),isTrue);
  });

  test('sales forecast is withheld for limited history and nets refunds and returns',(){
    final now=DateTime.utc(2026,10,16).millisecondsSinceEpoch, day=86400000;
    final state=emptyState()..['products']=[product('forecast-product-01')];
    state['events']=[
      for(final entry in [(20,'sale-forecast-001'),(12,'sale-forecast-002'),(8,'sale-forecast-003')])
        {'id':entry.$2,'type':'sale','date':now-entry.$1*day,'quantity':2,'revenue':200,'payment':'cash','allocations':[{'productId':'forecast-product-01','quantity':2}]},
      {'id':'refund-forecast-01','type':'refund','target':'sale-forecast-001','revenue':100,'quantity':0},
      {'id':'return-forecast-01','type':'return','target':'sale-forecast-001','quantity':1},
    ];
    final result=salesForecast(state,horizonDays:30,now:now);
    expect(result['limited'],isFalse);
    expect(result['saleSpanDays'],13);
    final row=objects(result['products']).single;
    expect(row['observedUnits'],5);
    expect(row['observedRevenue'],500);
    expect(row['forecastUnits'],5);
    expect(row['forecastRevenue'],500);
    final reversed=clone(state);
    reversed['events'].add(event(
      id:'undo-refund-forecast-01',
      type:'undo',
      target:'refund-forecast-01',
      note:'Refund reversal correction',
    ));
    final afterReversal=salesForecast(reversed,horizonDays:30,now:now);
    expect(objects(afterReversal['products']).single['observedRevenue'],600);
    final limited=emptyState()..['products']=[product('forecast-product-01')];
    limited['events']=[state['events'][0]];
    expect(salesForecast(limited,horizonDays:7,now:now)['limited'],isTrue);
    expect(objects(salesForecast(limited,horizonDays:7,now:now)['products']).single['forecastUnits'],isNull);
  });

  test('budget restock respects whole packs, budgets, missing cost and archived products',(){
    final products=[
      product('restock-urgent-01',minimum:4,cost:100),
      product('restock-slow-001',minimum:3,cost:400),
      product('restock-archived-01',minimum:9,cost:50,archived:true),
    ];
    final offers=[{
      'id':'offer-restock-01',
      'productId':'restock-urgent-01',
      'retailer':'Local store',
      'location':'',
      'packQuantity':4,
      'priceCents':280,
      'observedAt':10,
      'source':'manual',
    }];
    final plan=budgetRestockPlan(
      products,
      {'restock-urgent-01':0,'restock-slow-001':2,'restock-archived-01':0},
      offers,
      budgetCents:210,
    );
    expect(plan.map((p)=>p['productId']),['restock-urgent-01','restock-slow-001']);
    expect(plan.first['needed'],4);
    expect(plan.first['packQuantity'],4);
    expect(plan.first['plannedPacks'],0);
    expect(plan.first['planned'],0);
    expect(plan.first['estimatedCost'],0);
    expect(plan.first['budgetLimited'],isTrue);

    final funded=budgetRestockPlan(
      products,
      {'restock-urgent-01':0,'restock-slow-001':2},
      offers,
      budgetCents:280,
    );
    expect(funded.first['plannedPacks'],1);
    expect(funded.first['planned'],4);
    expect(funded.first['overbuy'],0);
    expect(funded.first['estimatedCost'],280);

    final overbuy=budgetRestockPlan(
      [product('restock-overbuy-01',minimum:5,cost:100)],
      {'restock-overbuy-01':0},
      [{
        'id':'offer-overbuy-01',
        'productId':'restock-overbuy-01',
        'retailer':'Local store',
        'location':'',
        'packQuantity':4,
        'priceCents':280,
        'observedAt':10,
        'source':'manual',
      }],
      budgetCents:560,
    );
    expect(overbuy.single['planned'],8);
    expect(overbuy.single['overbuy'],3);
    expect(overbuy.single['estimatedCost'],560);

    final missingCost=budgetRestockPlan(
      [product('restock-unknown-01',minimum:2,cost:0)],
      {'restock-unknown-01':0},
      const [],
      budgetCents:1000,
    );
    expect(missingCost.single['costKnown'],isFalse);
    expect(missingCost.single['estimatedCost'],isNull);
    expect(missingCost.single['planned'],0);
    expect(missingCost.single['costSource'],'missing cost');
  });
}
