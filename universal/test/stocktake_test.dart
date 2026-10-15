import 'package:flutter_test/flutter_test.dart';
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';
import 'package:business_tracker/core/legacy.dart';
import 'package:business_tracker/core/stocktakes.dart';

void main() {
  test('count discrepancy and damage are auditable inventory adjustments, never sales', () {
    final state=fixture()..['events']=[event(id:'stocktake-lot-0001',type:'restock',quantity:10,productId:'drink-cola-001',cost:2500)];
    var next=startStocktake(state,id:'stocktake-session-01',at:1780000000000);
    next=recordStocktakeCount(next,'stocktake-session-01','drink-cola-001',sellable:7,damaged:2,eventCount:1,countedAt:1780000001000);
    final review=stocktakePreview(next,'stocktake-session-01').single;
    expect(review['expected'],10);expect(review['variance'],-1);expect(review['projected'],7);
    final saved=confirmStocktake(next,'stocktake-session-01',at:1780000002000,newEventId:()=>'stocktake-event-${_next++}');
    final accounts=validateState(saved);
    expect(accounts.book.stock('drink-cola-001'),7);
    expect(accounts.summary()['revenue'],0);expect(accounts.salesProfit(objects(saved['products']))['profit'],0);
    expect(accounts.summary()['losses'],750);expect(accounts.summary()['purchases'],2500);
    final session=stocktakeSessions(saved).single;
    expect(session['status'],'completed');expect(session['adjustmentEventIds'],hasLength(2));
    expect(objects(saved['events']).where((e)=>e['stocktakeSessionId']=='stocktake-session-01').map((e)=>e['type']).toList(),['missing','damaged']);
    expect(decodeBackup(encodeBackup(saved)),saved);
  });

  test('sales and purchases made after a product count are retained during reconciliation', () {
    final state=fixture()..['events']=[event(id:'stocktake-lot-0001',type:'restock',quantity:10,productId:'drink-cola-001',cost:2500)];
    var next=startStocktake(state,id:'stocktake-session-02',at:1780000000000);
    next=recordStocktakeCount(next,'stocktake-session-02','drink-cola-001',sellable:8,damaged:2,eventCount:1,countedAt:1780000001000);
    next['events'].add(event(id:'stocktake-sale-00001',type:'sale',quantity:3,productId:'drink-cola-001',revenue:1200,payment:'cash'));
    next['events'].add(event(id:'stocktake-buy-000001',type:'restock',quantity:4,productId:'drink-cola-001',cost:1200));
    final confirmed=confirmStocktake(next,'stocktake-session-02',at:1780000003000,newEventId:()=>'stocktake-movement-${_next++}');
    final a=validateState(confirmed);
    expect(a.book.stock('drink-cola-001'),9); // 8 counted + four received − three sold.
    expect(a.summary()['revenue'],1200);expect(a.summary()['purchases'],3700);expect(a.summary()['losses'],500);
    expect(confirmed['events'][1]['id'],'stocktake-sale-00001');expect(confirmed['events'][2]['id'],'stocktake-buy-000001');
  });

  test('found stock is recorded without inventing purchase cost or purchase totals', () {
    final state=fixture()..['events']=[event(id:'stocktake-lot-0001',type:'restock',quantity:3,productId:'drink-cola-001',cost:900)];
    var next=startStocktake(state,id:'stocktake-session-03',at:1780000000000);
    next=recordStocktakeCount(next,'stocktake-session-03','drink-cola-001',sellable:5,damaged:0,eventCount:1,countedAt:1780000001000);
    final confirmed=confirmStocktake(next,'stocktake-session-03',at:1780000002000,newEventId:()=>'stocktake-found-0001');
    final a=validateState(confirmed),p=a.salesProfit(objects(confirmed['products']));
    expect(a.book.stock('drink-cola-001'),5);expect(a.book.value,900);expect(a.summary()['purchases'],900);
    expect(p['unknownCostUnits'],2);expect(p['futureProfit'],isNull);expect(p['revenue'],0);
    expect(objects(confirmed['events']).last['type'],'stocktake_found');
  });

  test('insufficient stock after newer sales blocks confirmation without rewriting movements', () {
    final state=fixture()..['events']=[event(id:'stocktake-lot-0001',type:'restock',quantity:10,productId:'drink-cola-001',cost:2500)];
    var next=startStocktake(state,id:'stocktake-session-04',at:1780000000000);
    next=recordStocktakeCount(next,'stocktake-session-04','drink-cola-001',sellable:4,damaged:1,eventCount:1,countedAt:1780000001000);
    next['events'].add(event(id:'stocktake-sale-00001',type:'sale',quantity:8,productId:'drink-cola-001',revenue:3200,payment:'cash'));
    final before=canonical(next);
    expect(stocktakePreview(next,'stocktake-session-04').single['conflict'],true);
    expect(()=>confirmStocktake(next,'stocktake-session-04',newEventId:()=>'stocktake-conflict-001'),throwsFormatException);
    expect(canonical(next),before);expect(objects(next['events']).last['id'],'stocktake-sale-00001');
  });

  test('repeated confirmation is idempotent and completed audit history is immutable', () {
    final state=fixture()..['events']=[event(id:'stocktake-lot-0001',type:'restock',quantity:4,productId:'drink-cola-001',cost:1000)];
    var next=startStocktake(state,id:'stocktake-session-05',at:1780000000000);
    next=recordStocktakeCount(next,'stocktake-session-05','drink-cola-001',sellable:4,damaged:0,eventCount:1,countedAt:1780000001000);
    final first=confirmStocktake(next,'stocktake-session-05',at:1780000002000),retry=confirmStocktake(first,'stocktake-session-05',at:1780000003000);
    expect(retry,first);expect(objects(retry['events']),hasLength(1));
    final edited=clone(first);stocktakeSessions(edited).single['completedAt']=1780000004000;
    expect(()=>validateStocktakeChanges(first,edited),throwsFormatException);
  });

  test('legacy backups without stocktake data decode and same-business restore retains new stocktake history', () {
    final original=fixture()..['events']=[event(id:'stocktake-lot-0001',type:'restock',quantity:4,productId:'drink-cola-001',cost:1000)];
    final oldFormat=clone(original)..remove('stocktakes');
    expect(stocktakeSessions(decodeBackup(encodeBackup(oldFormat))),isEmpty);
    final backup=clone(original),current=startStocktake(original,id:'stocktake-restore-01',at:1780000000000);
    expect(mergeBackup(current,backup)['stocktakes'],current['stocktakes']);
  });
}

int _next=0;
Obj fixture()=>emptyState()..['products']=[{'id':'drink-cola-001','name':'Cola','category':'Monster','variant':'500 ml','purchaseCost':250,'sellingPrice':400,'minimum':1,'barcode':'','photo':null}];
