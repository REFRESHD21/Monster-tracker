import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/codec.dart';
import 'repository.dart';

const businessFundsSecrets = FlutterSecureStorage();
const businessFundsSupabaseUrl = 'https://jmuxmgsbmnyqmetakhua.supabase.co';
// Supabase publishable/anon key. It is intentionally public; database access is
// still protected by Auth, RLS and admin-checked RPCs.
const businessFundsSupabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImptdXhtZ3NibW55cW1ldGFraHVhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMxNzE4NTYsImV4cCI6MjEwODc0Nzg1Nn0.oqWyp5gzF2nIPDtLvj35lSIeenHaus0jzxZ6m7I0SYk';

class BusinessFundsCloud {
  static const _accessKey = 'business-funds-access-token';
  static const _refreshKey = 'business-funds-refresh-token';
  static const _expiryKey = 'business-funds-token-expiry';
  static const _lastSyncKey = 'business-funds-last-sync';
  static const _errorKey = 'business-funds-sync-error';

  static Future<bool> get connected async => await businessFundsSecrets.read(key: _refreshKey) != null;
  static Future<String?> get lastSync => businessFundsSecrets.read(key: _lastSyncKey);
  static Future<String?> get lastError => businessFundsSecrets.read(key: _errorKey);

  static Uri _uri(String path, [Map<String,String>? query]) =>
      Uri.parse('$businessFundsSupabaseUrl$path').replace(queryParameters: query);

  static Future<Obj> _request(Uri uri, {String method='GET', String? token, Obj? body}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds:15);
    try {
      final request = await client.openUrl(method, uri).timeout(const Duration(seconds:20));
      request.headers.set('apikey', businessFundsSupabaseKey);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token != null) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(const Duration(seconds:25));
      final text = await utf8.decoder.bind(response).join().timeout(const Duration(seconds:25));
      if (text.length > 4*1024*1024) throw const FormatException('Cloud funds response is too large.');
      dynamic decoded;
      try { decoded = jsonDecode(text); } catch (_) { decoded = <String,dynamic>{'message':text}; }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map ? (decoded['msg'] ?? decoded['message'] ?? decoded['error_description'] ?? decoded['error']) : null;
        throw FormatException(message?.toString() ?? 'Cloud funds request failed (${response.statusCode}).');
      }
      if (decoded is! Map<String,dynamic>) throw const FormatException('Invalid cloud funds response.');
      return decoded;
    } finally {
      client.close(force:true);
    }
  }

  static Future<void> signIn(String email, String password) async {
    final result = await _request(
      _uri('/auth/v1/token', {'grant_type':'password'}),
      method:'POST',
      body:{'email':email.trim(),'password':password},
    );
    await _saveSession(result);
    await businessFundsSecrets.write(key:_errorKey,value:'');
  }

  static Future<void> _saveSession(Obj result) async {
    final access = result['access_token'], refresh = result['refresh_token'], expires = result['expires_in'];
    if (access is! String || refresh is! String || expires is! num) throw const FormatException('Supabase did not return a valid sign-in session.');
    await businessFundsSecrets.write(key:_accessKey,value:access);
    await businessFundsSecrets.write(key:_refreshKey,value:refresh);
    await businessFundsSecrets.write(key:_expiryKey,value:'${DateTime.now().millisecondsSinceEpoch + expires.toInt()*1000}');
  }

  static Future<String> _accessToken() async {
    final access = await businessFundsSecrets.read(key:_accessKey);
    final refresh = await businessFundsSecrets.read(key:_refreshKey);
    final expiry = int.tryParse(await businessFundsSecrets.read(key:_expiryKey) ?? '') ?? 0;
    if (refresh == null) throw const FormatException('Connect your Business Tracker admin account first.');
    if (access != null && expiry > DateTime.now().millisecondsSinceEpoch + 60000) return access;
    final result = await _request(
      _uri('/auth/v1/token', {'grant_type':'refresh_token'}),
      method:'POST',
      body:{'refresh_token':refresh},
    );
    await _saveSession(result);
    return result['access_token'] as String;
  }

  static Future<void> signOut() async {
    final access = await businessFundsSecrets.read(key:_accessKey);
    if (access != null) {
      try { await _request(_uri('/auth/v1/logout'),method:'POST',token:access); } catch (_) {}
    }
    for (final key in [_accessKey,_refreshKey,_expiryKey,_lastSyncKey,_errorKey]) {
      await businessFundsSecrets.delete(key:key);
    }
  }

  static Future<Obj> _snapshot(String token, String businessId) =>
      _request(_uri('/functions/v1/business-funds', {'business_id':businessId}),token:token);

  static Obj _normalise(Obj entry) {
    final value = clone(entry);
    value.remove('source');
    value.putIfAbsent('payment', () => null);
    value.putIfAbsent('saleId', () => null);
    value.putIfAbsent('note', () => '');
    return value;
  }

  static Future<int> sync(Repository repository) async {
    final token = await _accessToken();
    final state = repository.state;
    final businessId = state['businessId'];
    if (businessId is! String || !RegExp(r'^[0-9a-f-]{36}$',caseSensitive:false).hasMatch(businessId)) {
      throw const FormatException('This installation has no valid Business Tracker ID. No funds were changed.');
    }

    try {
      await _request(_uri('/functions/v1/business-funds'),method:'POST',token:token,body:{
        'business_id':businessId,
        'business_name':state['businessName'],
        'action':'register',
      });
      var remote = await _snapshot(token,businessId);
      var cloudEntries = (remote['entries'] as List? ?? const []).map((e)=>obj(e)).toList();
      final localEntries = objects(state['moneyEntries'] ?? const <dynamic>[]);
      final cloudById = {for(final e in cloudEntries)e['id'] as String:e};
      for (final local in localEntries) {
        final remoteEntry = cloudById[local['id']];
        if (remoteEntry != null && canonical(_normalise(remoteEntry)) != canonical(_normalise(local))) {
          throw FormatException('Funds history conflict for entry ${local['id']}. Nothing was overwritten.');
        }
      }
      final missing = localEntries.where((e)=>!cloudById.containsKey(e['id'])).toList();
      for (var offset=0; offset<missing.length; offset+=100) {
        final batch = missing.skip(offset).take(100).toList();
        await _request(_uri('/functions/v1/business-funds'),method:'POST',token:token,body:{
          'business_id':businessId,
          'business_name':state['businessName'],
          'action':'sync',
          'entries':batch,
        });
      }
      remote = await _snapshot(token,businessId);
      cloudEntries = (remote['entries'] as List? ?? const []).map((e)=>obj(e)).toList();
      final merged = <Obj>[for(final e in localEntries)clone(e)];
      final mergedIds = {for(final e in merged)e['id']};
      for (final entry in cloudEntries) {
        final normal = _normalise(entry);
        if (!mergedIds.contains(normal['id'])) {
          normal.remove('payment'); if (entry['payment'] != null) normal['payment']=entry['payment'];
          normal.remove('saleId'); if (entry['saleId'] != null) normal['saleId']=entry['saleId'];
          merged.add(normal);
          mergedIds.add(normal['id']);
        }
      }
      if (canonical(merged) != canonical(localEntries)) {
        final next = clone(repository.state);
        next['moneyEntries'] = merged;
        await repository.save(next);
      }
      await businessFundsSecrets.write(key:_lastSyncKey,value:DateTime.now().toIso8601String());
      await businessFundsSecrets.write(key:_errorKey,value:'');
      return (remote['balance'] as num).toInt();
    } catch (error) {
      await businessFundsSecrets.write(key:_errorKey,value:error.toString());
      rethrow;
    }
  }
}
