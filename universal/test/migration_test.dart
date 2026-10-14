import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:business_tracker/core/codec.dart';
import 'package:business_tracker/core/engine.dart';
import 'package:business_tracker/core/legacy.dart';
import 'package:business_tracker/services/backups.dart';
void main(){
  test('all six original backup versions remain readable without discarding source fields',(){
    for(final backup in strictJson(File('test/fixtures/legacy-versions.json').readAsStringSync()) as List){final s=importLegacy(canonical(backup));expect(s['legacy'],backup);expect(decodeBackup(encodeBackup(s)),s);}
  });
  test('Java v6 oracle includes transfers, GST, expense cancellation, partial refund reversal, physical return and receipts',(){
    final fixture=obj(strictJson(File('test/fixtures/full-domain.json').readAsStringSync()));
    final s=importLegacy(canonical(fixture['backup'])), totals=validateState(s).summary();
    for(final k in obj(fixture['expected']).keys){expect(totals[k],fixture['expected'][k],reason:k);}
    expect(s['attachments'][0]['data'],fixture['backup']['receipts'][0]['base64']);
    expect(s['legacy']['business']['receipts'],fixture['backup']['business']['receipts']);
  });
  test('Dart decrypts an actual Java-generated PBKDF2/AES-GCM backup',() async {
    final encrypted=base64Decode(File('test/fixtures/legacy-encrypted.txt').readAsStringSync());
    final s=await Backups.decode(encrypted,'fixture-password-123');expect(s['legacy']['version'],6);
    await expectLater(Backups.decode(encrypted,'wrong-password-123'),throwsFormatException);
    final corrupt=List<int>.of(encrypted);corrupt[corrupt.length-1]^=1;
    await expectLater(Backups.decode(corrupt,'fixture-password-123'),throwsFormatException);
  });
  test('encrypted universal backups round trip and reject truncation',()async{
    final s=emptyState();final b=await Backups.encrypt(s,'portable-password');expect(await Backups.decode(b,'portable-password'),s);
    await expectLater(Backups.decode(b.sublist(0,b.length-2),'portable-password'),throwsFormatException);
  });
}
