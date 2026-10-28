import 'dart:convert';
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/services.dart';
import 'repository.dart';
import '../core/codec.dart';
import '../core/engine.dart';
import '../core/sheet_snapshot.dart';
import '../core/sheet_upload.dart';
import 'sync.dart' show secrets;

/// Native SDK owns account credentials. No credentials enter portable state.
class GoogleSheets {
  static const scope='https://www.googleapis.com/auth/drive.file';
  static const webClient=String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const iosClient=String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  static bool get configured=>Platform.isIOS?iosClient.isNotEmpty:webClient.isNotEmpty;
  static GoogleSignIn get signIn=>_signIn ??=GoogleSignIn(scopes:[scope],clientId:Platform.isIOS?iosClient:null,serverClientId:webClient.isEmpty?null:webClient);
  static GoogleSignIn? _signIn;
  static Future<String> installation() async {
    final repo=await Repository.open(migrate:false);
    try{return (await repo.db.query('local_identity')).single['id'] as String;}finally{await repo.close();}
  }
  static Future<void> connect() async {
    if(!configured)throw const FormatException('Google connection is not configured in this build. The owner must register Android/iOS OAuth clients and build with their public client IDs. Advanced Apps Script remains available.');
    await signIn.signOut();
    final account=await signIn.signIn();
    if(account==null)throw const FormatException('Google account selection cancelled.');
    for(final key in ['sheets-google-id','sheets-mode','sheets-snapshot','sheets-last','sheets-error']){await secrets.delete(key:key);}
    await secrets.write(key:'sheets-account',value:account.id);
    await secrets.write(key:'sheets-email',value:account.email);
  }
  static Future<Obj> api(String path,{String method='GET',Obj? body}) async {
    final expected=await secrets.read(key:'sheets-account');
    final account=signIn.currentUser ?? await signIn.signInSilently(suppressErrors:false);
    if(expected==null || account==null || account.id!=expected)throw const FormatException('Reconnect Google Sheets to authorize this installation.');
    final uri=Uri.https(path.startsWith('/drive/')?'www.googleapis.com':'sheets.googleapis.com',path.split('?').first,path.contains('?')?Uri.splitQueryString(path.substring(path.indexOf('?')+1)):null);
    final client=HttpClient()..connectionTimeout=const Duration(seconds:20);
    try {
      final request=await client.openUrl(method,uri);request.followRedirects=false;
      (await account.authHeaders).forEach(request.headers.set);
      request.headers.contentType=ContentType.json;
      if(body!=null)request.write(jsonEncode(body));
      final response=await request.close().timeout(const Duration(seconds:45));
      final text=await utf8.decoder.bind(response).join().timeout(const Duration(seconds:45));
      if(response.statusCode==401){await account.clearAuthCache();throw const FormatException('Google authorization expired. Reconnect or retry while the app is open.');}
      if(response.statusCode==403)throw const FormatException('Google denied access. Check file access, enabled APIs and consent-screen test users.');
      if(response.statusCode==404)throw const FormatException('Spreadsheet missing or access removed. Choose another spreadsheet.');
      if(response.statusCode<200 || response.statusCode>=300)throw FormatException('Google upload unavailable (HTTP ${response.statusCode}). Local records are safe; retry when connected.');
      return obj(jsonDecode(text));
    }on SocketException{throw const FormatException('Offline. Changes are saved on this phone and will retry when connected.');}
    finally {client.close(force:true);}
  }
  static Future<List<Obj>> available() async {
    final result=<Obj>[];String? page;
    do {
      final query={'q':"mimeType='application/vnd.google-apps.spreadsheet' and trashed=false",'fields':'nextPageToken,files(id,name)','pageSize':'100',if(page!=null)'pageToken':page};
      final response=await api('/drive/v3/files?${Uri(queryParameters:query).query}');
      result.addAll(objects(response['files'] ?? []));page=response['nextPageToken'];
    }while(page!=null);
    return result;
  }
  static Future<Obj> create(String name) async {
    return api('/v4/spreadsheets',method:'POST',body:{'properties':{'title':name},'sheets':[{'properties':{'title':'About'}}]});
  }
  static Future<void> select(String id) async {
    await api('/v4/spreadsheets/$id?fields=spreadsheetId');
    await secrets.write(key:'sheets-google-id',value:id);
    await secrets.write(key:'sheets-mode',value:'google');
    await secrets.delete(key:'sheets-snapshot');await secrets.delete(key:'sheets-last');
    await secrets.delete(key:'sheets-error');
  }
  static Future<void> upload(Obj state,{bool force=false}) async {
    validateState(state);
    final id=await secrets.read(key:'sheets-google-id');
    if(id==null)throw const FormatException('Choose a spreadsheet first.');
    final installationId=await installation(),snapshot=sheetSnapshot(state);
    final hash=digest(snapshot);
    if(!force && await secrets.read(key:'sheets-snapshot')==hash)return;
    await uploadSnapshot(snapshot:snapshot,installation:installationId,
      metadata:()=>api('/v4/spreadsheets/$id?fields=sheets(properties)'),
      send:(requests)async{await api('/v4/spreadsheets/$id:batchUpdate',method:'POST',body:{'requests':requests});},
      acknowledge:(hash)=>secrets.write(key:'sheets-snapshot',value:hash));
    await secrets.write(key:'sheets-last',value:DateTime.now().toIso8601String());
    await secrets.write(key:'sheets-error',value:'');
  }
  static Future<void> disconnect() async {
    try{if(configured)await signIn.signOut();}finally {
      for(final key in ['sheets-mode','sheets-google-id','sheets-account','sheets-email','sheets-snapshot','sheets-url','sheets-token','sheets-auto','sheets-last','sheets-error']){await secrets.delete(key:key);}
    }
  }
}
