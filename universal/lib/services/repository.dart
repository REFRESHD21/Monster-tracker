import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/codec.dart';
import '../core/engine.dart';
import '../core/legacy.dart';

class Repository {
  final Database db; int revision=0; late Obj state;
  Repository._(this.db);
  static Future<Repository> open({bool migrate=true}) async {
    final db=await openDatabase(path.join(await getDatabasesPath(),'business-tracker-v1.db'),version:2,onUpgrade:(db,old,_) async {
      if(old==1){final rows=await db.query('tracker');await db.execute('CREATE TABLE state_chunks (seq INTEGER PRIMARY KEY,body TEXT NOT NULL)');if(rows.isNotEmpty){final text=rows.first['body'] as String;for(var i=0;i<text.length;i+=131072){await db.insert('state_chunks',{'seq':i~/131072,'body':text.substring(i,i+131072<text.length?i+131072:text.length)});} }await db.execute('ALTER TABLE tracker RENAME TO tracker_old');await db.execute('CREATE TABLE tracker (id INTEGER PRIMARY KEY CHECK(id=1),revision INTEGER NOT NULL)');await db.execute('INSERT INTO tracker(id,revision) SELECT id,revision FROM tracker_old');await db.execute('DROP TABLE tracker_old');}
    },onCreate:(db,_) async {
      await db.execute('CREATE TABLE tracker (id INTEGER PRIMARY KEY CHECK(id=1),revision INTEGER NOT NULL)');
      await db.execute('CREATE TABLE state_chunks (seq INTEGER PRIMARY KEY,body TEXT NOT NULL)');
      await db.execute('CREATE TABLE safety (id INTEGER PRIMARY KEY CHECK(id=1),legacy TEXT NOT NULL)');
      await db.execute("CREATE TRIGGER keep_safety BEFORE UPDATE ON safety BEGIN SELECT RAISE(ABORT,'Original migration backup is immutable'); END");
      await db.execute("CREATE TRIGGER retain_safety BEFORE DELETE ON safety BEGIN SELECT RAISE(ABORT,'Original migration backup is immutable'); END");
    });
    final r=Repository._(db);
    final loaded=await db.transaction((txn) async {final rows=await txn.query('tracker');if(rows.isEmpty)return null;final chunks=await txn.query('state_chunks',orderBy:'seq');return {'revision':rows.first['revision'],'body':chunks.map((x)=>x['body'] as String).join()};});
    if(loaded!=null){r.revision=loaded['revision'] as int;r.state=obj(strictJson(loaded['body'] as String));validateState(r.state);return r;}
    if(!migrate){await db.close();throw StateError('Initial migration has not finished.');}
    var initial=emptyState();
    if(migrate && Platform.isAndroid) {
      final legacy=await const MethodChannel('au.monster.tracker.plus/migration').invokeMethod<String>('legacyBackup');
      if(legacy!=null) {initial=importLegacy(legacy);await db.insert('safety',{'id':1,'legacy':legacy},conflictAlgorithm:ConflictAlgorithm.ignore);}
    }
    initial['businessId']=const Uuid().v4();r.state=initial;await r.save(initial);return r;
  }
  Future<void> save(Obj candidate) async {
    validateState(candidate);final before=objects(state['events']),after=objects(candidate['events']);
    if(canonical(after.take(before.length).toList())!=canonical(before) || state['legacy']!=null && canonical(state['legacy'])!=canonical(candidate['legacy']))throw const FormatException('Historical records cannot be overwritten.');
    final text=canonical(candidate);if(text.length>64*1024*1024)throw const FormatException('Data exceeds portable backup limit. Export and contact support.');
    await db.transaction((txn) async {
      final rows=await txn.query('tracker');
      if(rows.isEmpty){await txn.insert('tracker',{'id':1,'revision':1});}
      else {if(rows.first['revision']!=revision)throw StateError('Records changed in another task. Reopen and try again.');await txn.update('tracker',{'revision':revision+1},where:'id=1');}
      await txn.delete('state_chunks');
      for(var i=0;i<text.length;i+=131072){await txn.insert('state_chunks',{'seq':i~/131072,'body':text.substring(i,i+131072<text.length?i+131072:text.length)});}
    });
    revision++;state=clone(candidate);
  }
  Future<void> append(Obj e, [Obj? attachment]) async {final next=clone(state);(next['events'] as List).add(e);if(attachment!=null)(next['attachments'] as List).add({...attachment,'eventId':e['id']});await save(next);}
  Future<void> restore(Obj incoming) async {final next=mergeBackup(state,incoming);if((next['businessId'] as String).isEmpty)next['businessId']=state['businessId'];await save(next);}
  Future<void> close()=>db.close();
}
