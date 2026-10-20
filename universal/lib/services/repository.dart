import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/codec.dart';
import '../core/engine.dart';
import '../core/legacy.dart';
import '../core/products.dart';
import '../core/stocktakes.dart';

class Repository {
  final Database db; int revision=0; late Obj state;
  Repository._(this.db);
  // Separate foreground/background connections can contend for SQLite's writer.
  // Retry only lock contention after the failed transaction has rolled back.
  static Future<T> retryDatabase<T>(Future<T> Function() action) async {
    for(var attempt=0;;attempt++){
      try{return await action();}on DatabaseException catch(e){
        final detail=e.toString();
        if(attempt>=7 || !(detail.contains('SQLITE_BUSY') || detail.contains('database is locked') || detail.contains('database table is locked')))rethrow;
        await Future<void>.delayed(Duration(milliseconds:25*(attempt+1)));
      }
    }
  }
  static Future<T> transaction<T>(Database db,Future<T> Function(Transaction) action)=>retryDatabase(()=>db.transaction(action));
  static Future<Repository> open({bool migrate=true}) async {
    final db=await openDatabase(path.join(await getDatabasesPath(),'business-tracker-v1.db'),version:4,singleInstance:false,onUpgrade:(db,old,_) async {
      if(old==1){final rows=await db.query('tracker');await db.execute('CREATE TABLE state_chunks (seq INTEGER PRIMARY KEY,body TEXT NOT NULL)');if(rows.isNotEmpty){final text=rows.first['body'] as String;var seq=0;for(final chunk in stateChunks(text)){await db.insert('state_chunks',{'seq':seq++,'body':chunk});} }await db.execute('ALTER TABLE tracker RENAME TO tracker_old');await db.execute('CREATE TABLE tracker (id INTEGER PRIMARY KEY CHECK(id=1),revision INTEGER NOT NULL)');await db.execute('INSERT INTO tracker(id,revision) SELECT id,revision FROM tracker_old');await db.execute('DROP TABLE tracker_old');}
      if(old<4){await db.execute('CREATE TABLE task_lock (name TEXT PRIMARY KEY, owner TEXT NOT NULL, expires INTEGER NOT NULL)');await db.execute('CREATE TABLE local_identity (id TEXT PRIMARY KEY,migrated INTEGER NOT NULL)');await db.insert('local_identity',{'id':const Uuid().v4(),'migrated':1});}
      if(old<3)await db.execute('CREATE TABLE sync_ack (destination TEXT NOT NULL,business_id TEXT NOT NULL,record_id TEXT NOT NULL,hash TEXT NOT NULL,PRIMARY KEY(destination,business_id,record_id))');
    },onCreate:(db,_) async {
      await db.execute('CREATE TABLE tracker (id INTEGER PRIMARY KEY CHECK(id=1),revision INTEGER NOT NULL)');
      await db.execute('CREATE TABLE sync_ack (destination TEXT NOT NULL,business_id TEXT NOT NULL,record_id TEXT NOT NULL,hash TEXT NOT NULL,PRIMARY KEY(destination,business_id,record_id))');
      await db.execute('CREATE TABLE state_chunks (seq INTEGER PRIMARY KEY,body TEXT NOT NULL)');
      await db.execute('CREATE TABLE task_lock (name TEXT PRIMARY KEY, owner TEXT NOT NULL, expires INTEGER NOT NULL)');
      await db.execute('CREATE TABLE local_identity (id TEXT PRIMARY KEY,migrated INTEGER NOT NULL)');
      await db.insert('local_identity',{'id':const Uuid().v4(),'migrated':0});
      await db.execute('CREATE TABLE safety (id INTEGER PRIMARY KEY CHECK(id=1),legacy TEXT NOT NULL)');
      await db.execute("CREATE TRIGGER keep_safety BEFORE UPDATE ON safety BEGIN SELECT RAISE(ABORT,'Original migration backup is immutable'); END");
      await db.execute("CREATE TRIGGER retain_safety BEFORE DELETE ON safety BEGIN SELECT RAISE(ABORT,'Original migration backup is immutable'); END");
    });
    final r=Repository._(db);
    final loaded=await transaction(db,(txn) async {final rows=await txn.query('tracker');if(rows.isEmpty)return null;final chunks=await txn.query('state_chunks',orderBy:'seq');return {'revision':rows.first['revision'],'body':chunks.map((x)=>x['body'] as String).join()};});
    if(loaded!=null){r.revision=loaded['revision'] as int;r.state=obj(strictJson(loaded['body'] as String));validateState(r.state);return r;}
    if(!migrate){await db.close();throw StateError('Initial migration has not finished.');}
    var initial=emptyState();
    if(migrate && Platform.isAndroid) {
      final legacy=await const MethodChannel('au.monster.tracker.plus/migration').invokeMethod<String>('legacyBackup');
      if(legacy!=null) {initial=importLegacy(legacy);await db.insert('safety',{'id':1,'legacy':legacy},conflictAlgorithm:ConflictAlgorithm.ignore);}
    }
    initial['businessId']=const Uuid().v4();r.state=initial;await r.save(initial);return r;
  }
  Future<void> save(Obj candidate, {bool restoring=false}) async {
    validateProductChanges(state, candidate, restoring:restoring);
    validateStocktakeChanges(state, candidate);
    validateState(candidate);final before=objects(state['events']),after=objects(candidate['events']);
    if(canonical(after.take(before.length).toList())!=canonical(before) || state['legacy']!=null && canonical(state['legacy'])!=canonical(candidate['legacy']))throw const FormatException('Historical records cannot be overwritten.');
    final text=canonical(candidate);if(utf8.encode(text).length>64*1024*1024)throw const FormatException('Data exceeds portable backup limit. Export and contact support.');
    final expectedRevision=revision;
    await transaction(db,(txn) async {
      final rows=await txn.query('tracker');
      if(rows.isEmpty){await txn.insert('tracker',{'id':1,'revision':1});}
      else {if(rows.first['revision']!=expectedRevision)throw StateError('Records changed in another task. Reopen and try again.');await txn.update('tracker',{'revision':expectedRevision+1},where:'id=1');}
      await txn.delete('state_chunks');
      var seq=0;for(final chunk in stateChunks(text)){await txn.insert('state_chunks',{'seq':seq++,'body':chunk});}
    });
    revision=expectedRevision+1;state=clone(candidate);
  }
  Future<void> append(Obj e, [Obj? attachment]) async {
    final next=clone(state),events=objects(next['events']);
    final sourceId=e['target'];final source=events.where((old)=>old['id']==sourceId).firstOrNull;
    events.add(e);next['events']=events;
    if(e['type']=='refund' && source!=null && ['cash','card'].contains(source['payment'])){
      final entries=(next['moneyEntries'] ??= <dynamic>[]) as List;
      entries.add({'id':'refund-funds-${e['id']}','type':'refund','amount':(e['revenue'] as int)+(e['fee'] as int),'delta':-((e['revenue'] as int)+(e['fee'] as int)),'payment':source['payment'],'saleId':sourceId,'note':'Refund paid · ${source['productName'] ?? sourceId}','date':e['date'] as int});
    } else if(e['type']=='undo' && source!=null && ['single','deal','sale'].contains(source['type']) && ['cash','card'].contains(source['payment'])){
      final entries=(next['moneyEntries'] ??= <dynamic>[]) as List;
      final net=(source['revenue'] as int)-(source['fee'] as int);
      entries.add({'id':'correction-funds-${e['id']}','type':'correction','amount':net,'delta':-net,'payment':source['payment'],'saleId':sourceId,'note':'Reversed sale · ${source['productName'] ?? sourceId}','date':e['date'] as int});
    }
    if(attachment!=null)(next['attachments'] as List).add({...attachment,'eventId':e['id']});
    await save(next);
  }
  final Map<String, Future<bool>> _salesInFlight = {};
  final Map<String, Obj> _saleRequests = {};
  Future<bool> recordSale(Obj e, [Obj? attachment]) {
    final id=e['id'] as String,flight=_salesInFlight[e['id']];
    if(flight!=null){
      if(canonical(_saleRequests[id])!=canonical(e))return Future<bool>.error(const FormatException('This sale ID already has different details.'));
      return flight;
    }
    final future=_recordSale(e,attachment);
    _salesInFlight[id]=future;_saleRequests[id]=clone(e);
    void clear(){_salesInFlight.remove(id);_saleRequests.remove(id);}
    future.then<void>((_)=>clear(),onError:(Object error,StackTrace stack){clear();});
    return future;
  }
  Future<bool> _recordSale(Obj e,Obj? attachment) async {
    final id=e['id'] as String;
    final existing=objects(state['events']).where((old)=>old['id']==id).firstOrNull;
    if(existing!=null){
      if(canonical(existing)!=canonical(e))throw const FormatException('This sale ID already has different details.');
      return false;
    }
    if(e['type']!='sale')throw const FormatException('Expected a sale.');
    final next=clone(state);(next['events'] as List).add(e);if(['cash','card'].contains(e['payment']))next['lastPayment']=e['payment'];
    if(attachment!=null)(next['attachments'] as List).add({...attachment,'eventId':id});
    if(['cash','card'].contains(e['payment'])){
      final entries=(next['moneyEntries'] ??= <dynamic>[]) as List;
      entries.add({'id':'sale-funds-$id','type':'sale','amount':e['revenue'],'delta':(e['revenue'] as int)-(e['fee'] as int),'payment':e['payment'],'saleId':id,'note':'Sale proceeds · ${e['productName'] ?? id}','date':e['date'] as int});
    }
    await save(next);return true;
  }
  final Map<String,Future<bool>> _purchasesInFlight={};
  Future<bool> recordPurchase(List<Obj> entries,{bool affectFunds=false}) {
    if(entries.isEmpty) return Future<bool>.error(const FormatException('Add at least one purchase line.'));
    final batch=obj(entries.first['purchaseBatch']),id=batch['id'] as String;
    final flight=_purchasesInFlight[id];
    if(flight!=null)return flight;
    final future=_recordPurchase(entries,id,affectFunds);
    _purchasesInFlight[id]=future;
    future.then<void>((_)=>_purchasesInFlight.remove(id),onError:(Object error,StackTrace stack){_purchasesInFlight.remove(id);});
    return future;
  }
  Future<bool> _recordPurchase(List<Obj> entries,String purchaseId,bool affectFunds) async {
    final saved=objects(state['events']).where((e)=>e['purchaseBatch'] is Map && obj(e['purchaseBatch'])['id']==purchaseId).toList()
      ..sort((a,b)=>'${obj(a['purchaseLine'])['id']}'.compareTo('${obj(b['purchaseLine'])['id']}'));
    if(saved.isNotEmpty){
      final normalize=(List<Obj> rows){final ordered=List<Obj>.of(rows)..sort((a,b)=>'${obj(a['purchaseLine'])['id']}'.compareTo('${obj(b['purchaseLine'])['id']}'));return canonical(ordered.map((e){final x=clone(e);x.remove('id');x.remove('recordedAt');return x;}).toList());};
      if(normalize(saved)==normalize(entries))return false;
      throw const FormatException('This purchase ID already has different lines. No stock was added.');
    }
    final next=clone(state);(next['events'] as List).addAll(entries);
    validateState(next);
    await save(next);return true;
  }
  final Map<String,Future<bool>> _stocktakesInFlight={};
  Future<bool> confirmStocktakeSession(String sessionId) {
    final flight=_stocktakesInFlight[sessionId];
    if(flight!=null)return flight;
    final future=_confirmStocktakeSession(sessionId);
    _stocktakesInFlight[sessionId]=future;
    future.then<void>((_)=>_stocktakesInFlight.remove(sessionId),onError:(Object error,StackTrace stack){_stocktakesInFlight.remove(sessionId);});
    return future;
  }
  Future<bool> _confirmStocktakeSession(String sessionId) async {
    final next=confirmStocktake(state,sessionId);
    if(canonical(next)==canonical(state))return false;
    await save(next);return true;
  }
  Future<void> restore(Obj incoming) async {final next=mergeBackup(state,incoming);if((next['businessId'] as String).isEmpty)next['businessId']=state['businessId'];await save(next,restoring:true);}
  Future<void> close()=>db.close();
}
