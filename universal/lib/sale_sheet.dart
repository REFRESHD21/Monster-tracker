import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:uuid/uuid.dart';
import 'core/codec.dart';
import 'core/engine.dart';
import 'core/products.dart';

class SaleSheet extends StatefulWidget {
  final Obj product;
  final int stock;
  final String payment;
  final Future<void> Function(Obj event, Obj? receipt) onSave;
  final Future<Obj?> Function() pickReceipt;
  const SaleSheet({super.key, required this.product, required this.stock, required this.payment, required this.onSave, required this.pickReceipt});
  @override State<SaleSheet> createState() => _SaleSheetState();
}

class _SaleSheetState extends State<SaleSheet> {
  final quantity = TextEditingController(text:'1'), total = TextEditingController(), fee = TextEditingController(text:'0.00'), gst = TextEditingController(text:'0.00'), note = TextEditingController();
  final id = const Uuid().v4();
  late String payment = widget.payment;
  String mode = 'single', error = '';
  bool saving = false, saved = false, gstRegistered = false, editedTotal = false;
  Obj? receipt;
  DateTime date = DateTime.now().toUtc().add(const Duration(hours:8));
  @override void initState() {super.initState();total.text=amount(widget.product['sellingPrice']);}
  @override void dispose() {for(final c in [quantity,total,fee,gst,note]) {c.dispose();}super.dispose();}
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
      final q=integer(int.tryParse(quantity.text),1,10000);
      if(q>widget.stock)throw const FormatException('Not enough stock. Reduce the quantity or restock this product.');
      final e=event(id:id,type:'sale',quantity:q,productId:widget.product['id'],revenue:cents(total.text),payment:payment,fee:cents(fee.text),outputGst:gstRegistered?cents(gst.text):0,note:note.text.trim(),date:date.subtract(const Duration(hours:8)).millisecondsSinceEpoch);
      e['productName']=productLabel(widget.product);
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
        Text(productLabel(widget.product),style:Theme.of(context).textTheme.titleLarge),
        Text('${widget.stock} available · ${money(widget.product['sellingPrice'])} each'),
        const SizedBox(height:12),
        Wrap(spacing:8,runSpacing:8,children:[
          ChoiceChip(label:Text('1 item · ${money(widget.product['sellingPrice'])}'),selected:mode=='single',onSelected:(_)=>choose('single')),
          if(widget.product['twoItemPrice']!=null)ChoiceChip(label:Text('2-item deal · ${money(widget.product['twoItemPrice'])}'),selected:mode=='deal',onSelected:widget.stock<2?null:(_)=>choose('deal')),
          ChoiceChip(label:const Text('Custom quantity'),selected:mode=='custom',onSelected:(_)=>choose('custom')),
        ]),
        if(widget.product['twoItemPrice']==null)const Padding(padding:EdgeInsets.only(top:8),child:Text('No two-item deal configured for this product.')),
        Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Expanded(child:input(quantity,'Quantity',changed:(v)=>setState((){mode='custom';final q=int.tryParse(v);if(!editedTotal && q!=null && q>0 && q<=10000){try{total.text=amount(saleTotal(widget.product,q));}on FormatException{/* Validate on confirmation. */}}}))),
          const SizedBox(width:12),Expanded(child:input(total,'Total (AUD)',changed:(_)=>setState((){editedTotal=true;mode='custom';}))),
        ]),
        const Text('Payment recorded'),
        Wrap(spacing:12,children:[for(final p in ['cash','card'])ChoiceChip(label:Text(p=='cash'?'Cash':'Card / bank'),selected:payment==p,onSelected:(_)=>setState(()=>payment=p))]),
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
