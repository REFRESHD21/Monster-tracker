import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'core/business_modules.dart';
import 'core/codec.dart';
import 'core/engine.dart';
import 'core/products.dart';

class BusinessModuleScreen extends StatefulWidget {
  final String module;
  final Obj initialState;
  final Future<void> Function(Obj next) onSave;
  const BusinessModuleScreen({super.key, required this.module, required this.initialState, required this.onSave});

  @override
  State<BusinessModuleScreen> createState() => _BusinessModuleScreenState();
}

class _BusinessModuleScreenState extends State<BusinessModuleScreen> {
  late Obj state;
  int horizonDays = 30;
  String? offerProduct;
  final budget = TextEditingController(text:'0.00');
  final retailer = TextEditingController();
  final location = TextEditingController();
  final pack = TextEditingController(text:'4');
  final price = TextEditingController();

  @override
  void initState() {
    super.initState();
    state = clone(widget.initialState);
    state.putIfAbsent('customers', () => <dynamic>[]);
    state.putIfAbsent('customerPayments', () => <dynamic>[]);
    state.putIfAbsent('retailerOffers', () => <dynamic>[]);
  }

  @override
  void dispose() {
    for (final c in [budget, retailer, location, pack, price]) { c.dispose(); }
    super.dispose();
  }

  Future<void> save(Obj next, String message) async {
    await widget.onSave(next);
    if (!mounted) return;
    setState(() => state = clone(next));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> addCustomer() async {
    final name = TextEditingController(), phone = TextEditingController();
    final accepted = await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:const Text('Add customer'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:name,decoration:const InputDecoration(labelText:'Name or nickname')),
        TextField(controller:phone,decoration:const InputDecoration(labelText:'Optional contact')),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Save'))],
    ));
    if (accepted == true && name.text.trim().isNotEmpty) {
      final next=clone(state);
      objects(next['customers']).add({'id':const Uuid().v4(),'name':name.text.trim(),'phone':phone.text.trim().isEmpty?null:phone.text.trim(),'createdAt':DateTime.now().millisecondsSinceEpoch});
      await save(next,'Customer saved.');
    }
    name.dispose();phone.dispose();
  }

  Future<void> recordPayment(Obj customer, int balance) async {
    final amount=TextEditingController(), note=TextEditingController();
    final accepted=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:Text('Record payment · ${customer['name']}'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        Text('Outstanding balance: ${money(balance)}'),
        TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Payment received (AUD)')),
        TextField(controller:note,decoration:const InputDecoration(labelText:'Optional note')),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Record payment'))],
    ));
    if(accepted==true){
      try {
        final value=cents(amount.text);
        if(value<=0)throw const FormatException('Enter an amount greater than zero.');
        final next=clone(state);
        objects(next['customerPayments']).add({'id':const Uuid().v4(),'customerId':customer['id'],'amount':value,'date':DateTime.now().millisecondsSinceEpoch,'note':note.text.trim()});
        await save(next,'Payment recorded. It does not create another sale.');
      } catch(e) {
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));
      }
    }
    amount.dispose();note.dispose();
  }

  Future<void> addOffer() async {
    final products=objects(state['products']).where((p)=>p['archived']!=true).toList();
    if(products.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Add an active product before comparing offers.')));return;}
    offerProduct??=products.first['id'] as String;
    retailer.clear();location.clear();price.clear();
    pack.text='4';
    final accepted=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,update)=>AlertDialog(
      title:const Text('Add store offer'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<String>(value:offerProduct,decoration:const InputDecoration(labelText:'Exact product'),items:[for(final p in products)DropdownMenuItem(value:p['id'] as String,child:Text(productLabel(p)))],onChanged:(v)=>update(()=>offerProduct=v)),
        TextField(controller:retailer,decoration:const InputDecoration(labelText:'Store / retailer')),
        TextField(controller:location,decoration:const InputDecoration(labelText:'Location (optional)')),
        TextField(controller:pack,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Cans in offer')),
        TextField(controller:price,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Total offer price (AUD)')),
        const Text('Manual entry only. The app does not fetch or verify retailer prices.'),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Save offer'))],
    )));
    if(accepted==true){
      try {
        final quantity=integer(int.tryParse(pack.text),1,10000),amountCents=cents(price.text);
        if(retailer.text.trim().isEmpty || amountCents<=0)throw const FormatException('Enter a store and a positive price.');
        final next=clone(state);
        objects(next['retailerOffers']).add({'id':const Uuid().v4(),'productId':offerProduct,'retailer':retailer.text.trim(),'location':location.text.trim(),'packQuantity':quantity,'priceCents':amountCents,'observedAt':DateTime.now().millisecondsSinceEpoch,'source':'manual'});
        await save(next,'Store offer saved.');
      }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
    }
  }

  List<Widget> customerView() {
    final balances=customerBalances(state);
    final customers=customerRecords(state);
    return [
      const Text('IOU sales are recorded as sales in the main ledger. Later customer payments reduce the balance but do not create new sales.'),
      const SizedBox(height:12),
      FilledButton.icon(onPressed:addCustomer,icon:const Icon(Icons.person_add_alt_1),label:const Text('Add customer')),
      const SizedBox(height:8),
      if(customers.isEmpty)const Text('No customers yet. Add a name or nickname, then choose IOU as the payment method when recording a sale.'),
      for(final customer in customers) ...[
        Builder(builder:(context){
          final balance=balances[customer['id']]??0;
          final payments=customerPaymentRecords(state).where((p)=>p['customerId']==customer['id']).fold<int>(0,(sum,p)=>sum+(p['amount'] as int));
          final sales=objects(state['events']).where((e)=>e['payment']=='iou'&&e['customerId']==customer['id']).toList();
          return Card(child:ListTile(title:Text(customer['name'] as String),subtitle:Text('${sales.length} IOU sales · ${payments==0?'no payments recorded':'payments received ${money(payments)}'}${customer['phone']==null?'':'\n${customer['phone']}'}'),trailing:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text(balance<0?'Credit ${money(-balance)}':'Owes ${money(balance)}'),TextButton(onPressed:()=>recordPayment(customer,balance),child:const Text('Record payment'))])));
        }),
      ],
    ];
  }

  List<Widget> priceView() {
    final products=objects(state['products']).where((p)=>p['archived']!=true).toList();
    offerProduct??=products.isEmpty?null:products.first['id'] as String;
    final selected=products.where((p)=>p['id']==offerProduct).firstOrNull;
    final offers=selected==null?const <Obj>[]:offersForProduct(state,selected['id'] as String);
    return [
      const Text('Compare manually entered offers for the same product. Prices are not automatically collected or externally verified.'),
      const SizedBox(height:12),
      DropdownButtonFormField<String>(value:offerProduct,decoration:const InputDecoration(labelText:'Product'),items:[for(final p in products)DropdownMenuItem(value:p['id'] as String,child:Text(productLabel(p)))],onChanged:(v)=>setState(()=>offerProduct=v)),
      const SizedBox(height:8),
      FilledButton.icon(onPressed:addOffer,icon:const Icon(Icons.add),label:const Text('Add store offer')),
      if(offers.isEmpty)const Padding(padding:EdgeInsets.all(16),child:Text('No offers recorded for this product.')),
      for(final offer in offers)Card(child:ListTile(
        leading:const Icon(Icons.store_outlined),
        title:Text('${offer['retailer']} · ${money(offer['unitCost'])}/can'),
        subtitle:Text('${offer['packQuantity']} cans · ${money(offer['priceCents'])} total${(offer['location'] as String).isEmpty?'':' · ${offer['location']}'}\nManual entry · ${displayDate(offer['observedAt'])}'),
      )),
    ];
  }

  List<Widget> forecastView() {
    final forecast=salesForecast(state,horizonDays:horizonDays,now:DateTime.now().millisecondsSinceEpoch);
    return [
      const Text('Estimates use recorded sales from the prior 30 days. Stockout days are not modeled; projections are not guaranteed.'),
      const SizedBox(height:8),
      Wrap(spacing:8,children:[for(final days in [7,30,90])ChoiceChip(label:Text('Next $days days'),selected:horizonDays==days,onSelected:(_)=>setState(()=>horizonDays=days))]),
      Text('Observed window: ${forecast['observedDays']} days · ${forecast['saleCount']} sales'),
      if(forecast['limited']==true)const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('Limited history: record at least 3 sales spanning 7 days before numeric forecasts are shown.'))),
      for(final p in objects(forecast['products']))Card(child:ListTile(
        title:Text(p['name'] as String),
        subtitle:Text(forecast['limited']==true?'No reliable estimate yet':'Historical units: ${p['observedUnits']} · estimated next ${horizonDays} days: ${p['forecastUnits']} units'),
        trailing:Text(forecast['limited']==true?'Estimate unavailable':money(p['forecastRevenue'])),
      )),
    ];
  }

  List<Widget> restockView() {
    int budgetCents=0;
    try{budgetCents=cents(budget.text);}catch(_){}
    final accounts=validateState(state);
    final stock={for(final p in objects(state['products']))p['id'] as String:accounts.book.stock(p['id'] as String)};
    final plan=budgetRestockPlan(objects(state['products']),stock,retailerOfferRecords(state),budgetCents:budgetCents);
    return [
      const Text('Recommendations top products up only to their configured minimum stock. No order or purchase is placed. Costs use the best manually entered pack offer for that exact product, or the recorded purchase cost.'),
      TextField(controller:budget,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Available restock budget (AUD)'),onChanged:(_)=>setState((){})),
      const SizedBox(height:8),
      if(plan.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('No products are below their minimum-stock level.'))),
      for(final item in plan)Card(child:ListTile(
        title:Text(item['name'] as String),
        subtitle:Text(
          'On hand ' + item['stock'].toString() + ' · minimum ' + item['minimum'].toString() + ' · need ' + item['needed'].toString() + '\n' +
          (item['packQuantity'] > 1
              ? 'Plan ' + item['planned'].toString() + ' cans (' + item['plannedPacks'].toString() + ' × ' + item['packQuantity'].toString() + '-pack)'
              : 'Plan ' + item['planned'].toString() + ' cans') +
          (item['overbuy'] > 0 ? ' · ' + item['overbuy'].toString() + ' extra' : '') +
          ' · ' + (item['costSource'] as String) +
          ' · ' + (item['budgetLimited'] == true ? 'budget-limited' : 'within budget'),
        ),
        trailing:Text(item['estimatedCost'] is int ? money(item['estimatedCost']) : 'Cost unknown'),
      )),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final title=moduleNames[widget.module]??'Business module';
    final children=switch(widget.module){
      moduleCustomerAccounts=>customerView(),
      modulePriceComparison=>priceView(),
      moduleForecasting=>forecastView(),
      moduleSmartRestock=>restockView(),
      _=><Widget>[const Text('Unknown module.')],
    };
    return Scaffold(
      appBar:AppBar(title:Text(title)),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:children)),
    );
  }
}
