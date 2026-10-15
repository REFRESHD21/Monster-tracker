import 'package:flutter_test/flutter_test.dart';
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';
import 'package:business_tracker/core/legacy.dart';
import 'package:business_tracker/core/products.dart';

Obj product(String id, {int? deal}) => {'id':id,'name':'Flavour $id','category':'Drinks','variant':'500 ml','purchaseCost':100,'sellingPrice':350,'minimum':2,'barcode':'','photo':null,if(deal!=null)'twoItemPrice':deal};
Obj state() {final s=emptyState();s['businessId']='business-test-001';s['products']=[product('flavour-test-001',deal:600),product('flavour-test-002')];return s;}
void main() {
  test('deals are explicit, product-specific and never rewrite historical amounts',(){
    final s=state(), p=objects(s['products']).first;
    s['events']=[event(id:'restock-test-001',type:'restock',quantity:10,productId:p['id'],cost:1000),event(id:'sale-before-001',type:'sale',quantity:2,productId:p['id'],revenue:777,payment:'cash')];
    final history=canonical(s['events']);
    expect(saleTotal(p,1),350);expect(saleTotal(p,2),700);expect(saleTotal(p,2,deal:true),600);
    expect(()=>saleTotal(objects(s['products'])[1],2,deal:true),throwsFormatException);
    expect(()=>saleTotal(p,3,deal:true),throwsFormatException);
    p['twoItemPrice']=550;validateState(s);expect(canonical(s['events']),history);expect(validateState(s).summary()['revenue'],777);
    p['twoItemPrice']=null;expect(()=>saleTotal(p,2,deal:true),throwsFormatException);
  });
  test('2.0.0 products default active without a deal and optional fields are validated',(){
    final s=state(),p=objects(s['products'])[1];expect(isArchived(p),false);expect(p['twoItemPrice'],null);validateState(s);
    p['twoItemPrice']=0;expect(()=>validateState(s),throwsFormatException);p['twoItemPrice']=500;
    p['archived']='yes';expect(()=>validateState(s),throwsFormatException);p['archived']=false;
    s['lastPayment']='provider';expect(()=>validateState(s),throwsFormatException);
  });
  test('only unused unreferenced products may be permanently deleted',(){
    final s=state();expect(productRemoval(s,'flavour-test-001').canDelete,true);
    final deleted=clone(s);(deleted['products'] as List).removeAt(0);validateProductChanges(s,deleted);
    final orphaned=clone(deleted);orphaned['otherReference']={'productId':'flavour-test-001'};expect(()=>validateProductChanges(s,orphaned),throwsFormatException);
    s['otherReference']={'productId':'flavour-test-001'};
    expect(productRemoval(s,'flavour-test-001').canDelete,false);expect(productRemoval(s,'flavour-test-001').canArchive,true);
    expect(()=>validateProductChanges(s,deleted),throwsFormatException);
  });
  test('stock and pending transactions block archive; zero-stock history permits archive only',(){
    final s=state();s['events']=[event(id:'restock-test-001',type:'restock',quantity:2,productId:'flavour-test-001',cost:200)];
    final archived=clone(s);archived['products'][0]['archived']=true;
    expect(productRemoval(s,'flavour-test-001').explanation,contains('2 units remain'));
    expect(()=>validateProductChanges(s,archived),throwsFormatException);
    s['events'].add(event(id:'sale-test-00001',type:'sale',quantity:2,productId:'flavour-test-001',revenue:600,payment:'card'));
    final zero=clone(s);zero['products'][0]['archived']=true;validateProductChanges(s,zero);
    expect(productRemoval(s,'flavour-test-001').canDelete,false);expect(productRemoval(s,'flavour-test-001').canArchive,true);
    s['events'][1]['reservedRefund']=100;
    expect(productRemoval(s,'flavour-test-001').pending,1);expect(productRemoval(s,'flavour-test-001').canArchive,false);
    expect(productRemoval(s,'flavour-test-001').explanation,contains('pending'));
  });
  test('archiving, restoring and backups retain names, prices, payment and reports',(){
    final s=state();s['lastPayment']='card';s['events']=[event(id:'restock-test-001',type:'restock',quantity:2,productId:'flavour-test-001',cost:200),event(id:'sale-test-00001',type:'sale',quantity:2,productId:'flavour-test-001',revenue:600,payment:'card')];
    final totals=validateState(s).summary(),archived=clone(s);archived['products'][0]['archived']=true;validateProductChanges(s,archived);
    expect(activeProducts(archived).map((p)=>p['id']),['flavour-test-002']);
    final restored=decodeBackup(encodeBackup(archived));expect(restored,archived);expect(validateState(restored).summary(),totals);
    validateProductChanges(emptyState(),restored,restoring:true);
    expect(restored['products'][0]['name'],s['products'][0]['name']);expect(restored['products'][0]['twoItemPrice'],600);expect(restored['lastPayment'],'card');
    expect(()=>saleTotal(restored['products'][0],1),throwsFormatException);
    final newStock=clone(restored);newStock['events'].add(event(id:'restock-test-002',type:'restock',quantity:1,productId:'flavour-test-001',cost:100));
    expect(()=>validateProductChanges(restored,newStock),throwsFormatException);
    restored['products'][0]['archived']=false;expect(activeProducts(restored).length,2);expect(validateState(restored).summary(),totals);
  });
  test('transfers, receipts and generic pending references cannot be orphaned',(){
    final s=state();s['pendingTransactions']=[{'productId':'flavour-test-002','status':'pending'}];
    expect(productRemoval(s,'flavour-test-002').canArchive,false);
    s.remove('pendingTransactions');s['events']=[event(id:'restock-test-001',type:'restock',quantity:2,productId:'flavour-test-001',cost:200),{...event(id:'transfer-test-001',type:'transfer',quantity:2),'from':'flavour-test-001','to':'flavour-test-002'}];
    expect(productRemoval(s,'flavour-test-001').stock,0);expect(productRemoval(s,'flavour-test-001').canDelete,false);
  });
  test('reimporting a 2.0.0 backup cannot silently reset settings it never contained',(){
    final old=state();for(final p in objects(old['products'])){p.remove('twoItemPrice');p.remove('archived');}
    final current=clone(old);current['products'][0]['twoItemPrice']=600;current['products'][0]['archived']=true;current['lastPayment']='card';
    final restored=mergeBackup(current,decodeBackup(encodeBackup(old)));
    expect(restored['products'][0]['twoItemPrice'],600);expect(restored['products'][0]['archived'],true);expect(restored['lastPayment'],'card');
    final explicit=clone(restored);explicit['products'][0]['twoItemPrice']=null;explicit['products'][0]['archived']=false;explicit['lastPayment']='cash';
    final chosen=mergeBackup(current,decodeBackup(encodeBackup(explicit)));
    expect(chosen['products'][0]['twoItemPrice'],null);expect(chosen['products'][0]['archived'],false);expect(chosen['lastPayment'],'cash');
  });
  test('unreceived supplier lines block archive even with zero on-hand stock',(){
    final s=state();s['legacy']={'business':{'documents':[{'id':'purchase-pending-001','lines':[{'id':'pending-line-001','productId':'flavour-test-001','stock':true,'packs':2,'packSize':6}]}],'deliveries':[{'lineId':'pending-line-001','quantity':4}],'cancellations':[]}};
    final removal=productRemoval(s,'flavour-test-001');expect(removal.stock,0);expect(removal.pending,1);expect(removal.canArchive,false);expect(removal.explanation,contains('supplier'));
    s['legacy']['business']['deliveries'][0]['quantity']=12;expect(productRemoval(s,'flavour-test-001').canArchive,true);
    s['legacy']['business']['deliveries']=[];s['legacy']['business']['cancellations']=[{'documentId':'purchase-pending-001'}];expect(productRemoval(s,'flavour-test-001').canArchive,true);
  });

}
