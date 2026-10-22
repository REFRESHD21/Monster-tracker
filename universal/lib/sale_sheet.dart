import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:uuid/uuid.dart';
import 'core/codec.dart';
import 'core/engine.dart';
import 'core/products.dart';
import 'core/bundles.dart';

class SaleSheet extends StatefulWidget {
  final Obj product;
  final int stock;
  final String payment;
  final List<Obj> customers;
  final Obj? bundle;
  final List<Obj>? cartLines;
  final Future<void> Function(Obj event, Obj? receipt) onSave;
  final Future<Obj?> Function() pickReceipt;
  const SaleSheet({super.key, required this.product, required this.stock, required this.payment, this.customers = const <Obj>[], this.bundle, this.cartLines, required this.onSave, required this.pickReceipt});
  @override State<SaleSheet> createState() => _SaleSheetState();
}

class _SaleSheetState extends State<SaleSheet> {
  final quantity = TextEditingController(text:'1'), total = TextEditingController(), fee = TextEditingController(text:'0.00'), gst = TextEditingController(text:'0.00'), note = TextEditingController();
  final mixMatchPrice = TextEditingController(text:'6.00');
  final id = const Uuid().v4();
  final recordedAt = DateTime.now().millisecondsSinceEpoch;
  late String payment = widget.payment;
  String mode = 'single', error = '';
  String? customerId;
  bool saving = false, saved = false, gstRegistered = false, editedTotal = false, mixMatch = false;
  Obj? receipt;
  DateTime date = DateTime.now().toUtc().add(const Duration(hours:8));
  @override void initState() {super.initState();final subtotal=widget.cartLines==null?widget.product['sellingPrice'] as int? ?? 0:widget.cartLines!.fold<int>(0,(sum,line)=>sum+(line['unitPrice'] as int)*(line['quantity'] as int));total.text=amount(subtotal);}
  bool get canMixMatch => widget.cartLines!=null && widget.cartLines!.where((line)=>line['kind']=='product').fold<int>(0,(sum,line)=>sum+(line['quantity'] as int))>=2;
  int cartTotal(){
    final productPrices=<int>[];var otherTotal=0;
    for(final line in widget.cartLines ?? const <Obj>[]){
      final q=line['quantity'] as int,unit=line['unitPrice'] as int;
      if(line['kind']=='product'){for(var i=0;i<q;i++)productPrices.add(unit);}else{otherTotal+=unit*q;}
    }
    if(!mixMatch || productPrices.length<2)return otherTotal+productPrices.fold<int>(0,(sum,p)=>sum+p);
    final deal=cents(mixMatchPrice.text);var result=otherTotal;
    for(var i=0;i<productPrices.length;i+=2){result+=i+1<productPrices.length?deal:productPrices[i];}
    return result;
  }
  @override void dispose() {for(final c in [quantity,total,fee,gst,note,mixMatchPrice]) {c.dispose();}super.dispose();}
  void choose(String selected) => setState(() {
    mode=selected;editedTotal=false;error='';
    if(selected!='custom')quantity.text=selected=='deal'?'2':'1';
    final q=int.tryParse(quantity.text);
    if(q!=null && q>0 && q<=10000){try{total.text=amount(saleTotal(widget.product,q,deal:selected=='deal'));}on FormatException{/* Validate on confirmation. */}}
  });
  Widget input(TextEditingController controller,String label,{ValueChanged<String>? changed}) => Padding(padding:const EdgeInsets.symmetric(vertical:6),child:TextField(controller:controller,onChanged:changed,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:label)));
  Future<void> submit() async {
    // Set synchronously before the first await; two taps share one draft ID.
    if(saving || saved)return;
    setState((){saving=true;error='';});
    try {
      final q=widget.cartLines==null?integer(int.tryParse(quantity.text),1,10000):1;
      if(widget.product['sellingPrice']==null)throw const FormatException('Set a selling price before recording this sale.');
      if(widget.cartLines==null && q>widget.stock)throw const FormatException('Not enough stock. Reduce the quantity or restock this product.');
      if(payment=='iou' && customerId==null)throw const FormatException('Choose a customer for this IOU.');
      final revenue=cents(total.text),actualFee=payment=='iou'?0:cents(fee.text),tax=gstRegistered?cents(gst.text):0;
      Obj e;
      if(widget.cartLines!=null){
        final bundleLine=widget.cartLines!.where((line)=>line['kind']=='bundle').firstOrNull;
        final individual=[for(final line in widget.cartLines!.where((line)=>line['kind']=='product')) {'productId':line['id'],'quantity':line['quantity']}];
        if(bundleLine!=null){
          final b=obj(bundleLine['bundle']);
          e=bundleSaleEvent(id:id,bundle:b,bundleQuantity:bundleLine['quantity'] as int,revenue:revenue,payment:payment,note:note.text.trim(),date:date.subtract(const Duration(hours:8)).millisecondsSinceEpoch,recordedAt:recordedAt,customerId:customerId,fee:actualFee,outputGst:tax,individualLines:individual);
        }else{
          final allocations=<String,int>{};
          for(final line in widget.cartLines!){final productId=line['id'] as String;allocations[productId]=(allocations[productId]??0)+(line['quantity'] as int);}
          final physical=allocations.values.fold<int>(0,(sum,q)=>sum+q);
          e=event(id:id,type:'sale',quantity:physical,revenue:revenue,payment:payment,fee:actualFee,outputGst:tax,note:note.text.trim(),date:date.subtract(const Duration(hours:8)).millisecondsSinceEpoch);
          e['allocations']=[for(final entry in allocations.entries) {'productId':entry.key,'quantity':entry.value}];
        }
      }else if(widget.bundle==null){
        e=event(id:id,type:'sale',quantity:q,productId:widget.product['id'],revenue:revenue,payment:payment,fee:actualFee,outputGst:tax,note:note.text.trim(),date:date.subtract(const Duration(hours:8)).millisecondsSinceEpoch);
      }else{
        e=bundleSaleEvent(id:id,bundle:widget.bundle!,bundleQuantity:q,revenue:revenue,payment:payment,note:note.text.trim(),date:date.subtract(const Duration(hours:8)).millisecondsSinceEpoch,recordedAt:recordedAt,customerId:customerId,fee:actualFee,outputGst:tax);
      }
      if(payment=='iou')e['customerId']=customerId;
      e['recordedAt']=recordedAt;
      if(widget.cartLines!=null){
        e['productName']=widget.cartLines!.map((line)=>'${line['quantity']} × ${line['name']}').join(', ');
      }else if(widget.bundle!=null){
        e['productName']=widget.bundle!['name'];
      }else{
        e['productName']=productLabel(widget.product);
      }
      e['saleOption']=mode;
      await widget.onSave(e,receipt);
      saved=true;
      if(mounted)Navigator.pop(context,true);
    } catch(e) {if(mounted)setState(()=>error=e is FormatException?e.message:'$e');}
    finally {if(mounted)setState(()=>saving=false);}
  }
  Future<void> ocr() async {
    final file=File('${Directory.systemTemp.path}/sale-receipt-$id.jpg');
    final recognizer=TextRecognizer();
    try {
      await file.writeAsBytes(attachmentBytes(receipt!));
      final result=await recognizer.processImage(InputImage.fromFilePath(file.path));
      if(mounted)await showDialog<void>(context:context,builder:(c)=>AlertDialog(title:const Text('OCR suggestions · review manually'),content:SingleChildScrollView(child:SelectableText(result.text)),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Close'))]));
    } catch(e) {if(mounted)setState(()=>error='$e');}
    finally {await recognizer.close();if(await file.exists())await file.delete();}
  }
  @override Widget build(BuildContext context) => PopScope(canPop:!saving,child:SafeArea(child:Padding(
    padding:EdgeInsets.only(left:20,right:20,bottom:MediaQuery.viewInsetsOf(context).bottom+12),
    child:ConstrainedBox(constraints:BoxConstraints(maxHeight:MediaQuery.sizeOf(context).height*.88),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Flexible(child:SingleChildScrollView(child:IgnorePointer(ignoring:saving,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(widget.cartLines==null?productLabel(widget.product):'Sale cart',style:Theme.of(context).textTheme.titleLarge),
        if(widget.cartLines!=null)...[
          const Text('Items in this sale'),
          for(final line in widget.cartLines!)Text('${line['quantity']} × ${line['name']} · ${money((line['unitPrice'] as int)*(line['quantity'] as int))}'),
        ],
        if(widget.bundle!=null) ...[
          const Text('Bundle contents'),
          for(final component in objects(widget.bundle!['components'])) Text('${component['quantity']} × ${productLabel({'name':component['productName'] ?? component['productId'], 'variant':''})}'),
        ],
        if(widget.cartLines==null)Text('${widget.stock} available · ${widget.product['sellingPrice'] is int?money(widget.product['sellingPrice'] as int):'selling price not set'} ${widget.bundle==null?'each':'per bundle'}'),
        const SizedBox(height:12),
        if(widget.cartLines==null)...[
        Wrap(spacing:8,runSpacing:8,children:[
          ChoiceChip(label:Text('${widget.bundle==null?'1 item':'1 bundle'} · ${widget.product['sellingPrice'] is int?money(widget.product['sellingPrice'] as int):'Price not set'}'),selected:mode=='single',onSelected:(_)=>choose('single')),
          if(widget.product['twoItemPrice']!=null)ChoiceChip(label:Text('2-item deal · ${money(widget.product['twoItemPrice'])}'),selected:mode=='deal',onSelected:widget.stock<2?null:(_)=>choose('deal')),
          ChoiceChip(label:const Text('Custom quantity'),selected:mode=='custom',onSelected:(_)=>choose('custom')),
        ]),
        if(widget.product['twoItemPrice']==null)const Padding(padding:EdgeInsets.only(top:8),child:Text('No two-item deal configured for this product.')),
        Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Expanded(child:input(quantity,'Quantity',changed:(v)=>setState((){mode='custom';final q=int.tryParse(v);if(!editedTotal && q!=null && q>0 && q<=10000){try{total.text=amount(saleTotal(widget.product,q));}on FormatException{/* Validate on confirmation. */}}}))),
          const SizedBox(width:12),Expanded(child:input(total,'Total (AUD)',changed:(_)=>setState((){editedTotal=true;mode='custom';}))),
        ]),
        ],
        if(widget.cartLines!=null)...[
          if(canMixMatch)...[
            CheckboxListTile(contentPadding:EdgeInsets.zero,value:mixMatch,onChanged:(value)=>setState((){mixMatch=value??false;editedTotal=false;mode=mixMatch?'mix-match':'custom';try{total.text=amount(cartTotal());}on FormatException{/* Keep the current total until the pair price is valid. */}}),title:const Text('Apply mix-and-match deal'),subtitle:const Text('Every pair of individual products can use the deal price; bundles are excluded.'),controlAffinity:ListTileControlAffinity.leading),
            if(mixMatch)input(mixMatchPrice,'Price for each pair (AUD)',changed:(_)=>setState((){if(!editedTotal){try{total.text=amount(cartTotal());}on FormatException{/* Validate when confirming. */}}})),
          ],
          input(total,'Total (AUD)',changed:(_)=>setState(()=>editedTotal=true)),
        ],
        const Text('Payment recorded'),
        Wrap(spacing:12,children:[for(final p in ['cash','card',if(widget.customers.isNotEmpty)'iou'])ChoiceChip(label:Text(p=='cash'?'Cash':p=='card'?'Card / bank':'IOU'),selected:payment==p,onSelected:(_)=>setState((){payment=p;if(p=='iou')fee.text='0.00';}))]),
        if(payment=='iou')...[
          DropdownButtonFormField<String>(value:customerId,decoration:const InputDecoration(labelText:'Customer'),items:[for(final customer in widget.customers)DropdownMenuItem(value:customer['id'] as String,child:Text(customer['name'] as String))],onChanged:(value)=>setState(()=>customerId=value)),
          const Text('This completed sale is recorded in sales revenue and the customer’s outstanding balance. Payments received later do not create new sales.'),
        ],
        ExpansionTile(tilePadding:EdgeInsets.zero,title:const Text('More details'),subtitle:const Text('Fee, GST, receipt, date or note'),children:[
          input(fee,'Actual payment fee (AUD)'),
          CheckboxListTile(contentPadding:EdgeInsets.zero,value:gstRegistered,onChanged:(v)=>setState(()=>gstRegistered=v!),title:const Text('GST registered: record output GST')),
          if(gstRegistered)input(gst,'GST included (AUD)'),
          TextField(controller:note,decoration:const InputDecoration(labelText:'Note / reference')),
          TextButton.icon(onPressed:()async{final selected=await showDatePicker(context:context,initialDate:date,firstDate:DateTime(2000),lastDate:DateTime(2099));if(selected!=null)setState(()=>date=DateTime.utc(selected.year,selected.month,selected.day,date.hour,date.minute));},icon:const Icon(Icons.calendar_today_outlined),label:Text(displayDate(date.subtract(const Duration(hours:8)).millisecondsSinceEpoch))),
          TextButton.icon(onPressed:()async{try{final picked=await widget.pickReceipt();if(picked!=null && mounted)setState(()=>receipt=picked);}catch(e){if(mounted)setState(()=>error='$e');}},icon:const Icon(Icons.attach_file),label:Text(receipt==null?'Attach receipt':'Receipt attached · replace')),
          if(receipt!=null && receipt!['mime']!='application/pdf')TextButton(onPressed:ocr,child:const Text('Read receipt text (offline OCR)')),
          const Text('Manual bookkeeping only. Recording a card sale does not charge a card.'),
        ]),
      ])))),
      if(error.isNotEmpty)Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text(error,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      const SizedBox(height:8),
      FilledButton.icon(key:const ValueKey('confirm-sale'),onPressed:saving?null:submit,icon:saving?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.check),label:Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(saving?'Saving…':'Confirm sale · \$${total.text}'))),
      TextButton(onPressed:saving?null:()=>Navigator.pop(context),child:const Text('Cancel')),
    ])),
  )));
}
