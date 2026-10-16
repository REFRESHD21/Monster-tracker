import 'dart:typed_data';
import 'package:flutter/services.dart';
class BackupDestination {
  static const channel=MethodChannel('au.monster.tracker.plus/backup-destination');
  static Future<String?> choose()=>channel.invokeMethod<String>('chooseFolder');
  static Future<void> write(String folder,String name,Uint8List bytes)=>channel.invokeMethod<void>('writeBackup',{'folder':folder,'name':name,'bytes':bytes});
}
