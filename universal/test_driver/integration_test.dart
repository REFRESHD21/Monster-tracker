import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';
Future<void> main()=>integrationDriver(onScreenshot:(String name,List<int> bytes,[Map<String,Object?>? args]) async {await Directory('device-evidence').create(recursive:true);await File('device-evidence/$name.png').writeAsBytes(bytes);return true;});
