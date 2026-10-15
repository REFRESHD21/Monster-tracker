import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';
import 'package:business_tracker/services/repository.dart';
import '../test_support/product_flow.dart';

void main(){
  testWidgets('compact-phone product picker, deal edit, sale, archive and restore', (tester) async {
    tester.view.physicalSize=const Size(320,640);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    FlutterSecureStorage.setMockInitialValues({});
    await tester.runAsync(() async {
      sqfliteFfiInit();databaseFactory=databaseFactoryFfiNoIsolate;
      final folder=await Directory.systemTemp.createTemp('tracker-ui-');
      await databaseFactory.setDatabasesPath(folder.path);
      final repo=await Repository.open();
      try {
        final next=clone(repo.state);next['products']=[{'id':'device-product-001','name':'Skincare cream','category':'Skincare','variant':'50 ml','purchaseCost':123,'sellingPrice':555,'minimum':3,'barcode':'00123456789','photo':null}];await repo.save(next);
        await repo.append(event(id:'device-restock-001',type:'restock',quantity:9,productId:'device-product-001',cost:1107));
        await repo.append(event(id:'device-sale-00001',type:'sale',quantity:4,productId:'device-product-001',revenue:2220,payment:'cash'));
        await repo.append(event(id:'device-refund-001',type:'refund',target:'device-sale-00001',revenue:555));
        await repo.append(event(id:'device-return-001',type:'return',target:'device-sale-00001',quantity:1));
        await exerciseProductFlow(tester,repo,screenshot:(_)async{});
      } finally {
        await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
        await repo.close();await folder.delete(recursive:true);
      }
    });
  });
}
