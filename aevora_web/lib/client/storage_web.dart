import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';

import 'blob_types.dart';

/// تنفيذ طبقة التخزين المحلية على المتصفح عبر IndexedDB — كل بيانات المستخدم
/// تبقى على جهازه، ولا تُرسل أي ملفات أو ذكريات أو محادثات إلى أي خادم.
class LocalDb {
  static const _dbName = 'aevora_local';
  static const _version = 1;

  static Database? _db;

  static Future<Database> get _database async {
    final existing = _db;
    if (existing != null) return existing;
    final db = await idbFactoryBrowser.open(_dbName, version: _version,
        onUpgradeNeeded: (e) {
      final database = e.database;
      if (!database.objectStoreNames.contains('kv')) {
        database.createObjectStore('kv', keyPath: 'key');
      }
      if (!database.objectStoreNames.contains('files')) {
        database.createObjectStore('files', keyPath: 'id');
      }
      if (!database.objectStoreNames.contains('blobs')) {
        database.createObjectStore('blobs', keyPath: 'id');
      }
      if (!database.objectStoreNames.contains('chunks')) {
        database.createObjectStore('chunks', keyPath: 'id');
      }
    });
    _db = db;
    return db;
  }

  // ---------- عام ----------
  static Future<void> put(String store, Object value) async {
    final db = await _database;
    final txn = db.transaction(store, idbModeReadWrite);
    await txn.objectStore(store).put(value);
    await txn.completed;
  }

  static Future<Object?> get(String store, Object key) async {
    final db = await _database;
    final txn = db.transaction(store, idbModeReadOnly);
    final v = await txn.objectStore(store).getObject(key);
    await txn.completed;
    return v;
  }

  static Future<List<Object>> getAll(String store) async {
    final db = await _database;
    final txn = db.transaction(store, idbModeReadOnly);
    final v = await txn.objectStore(store).getAll();
    await txn.completed;
    return v;
  }

  static Future<void> delete(String store, Object key) async {
    final db = await _database;
    final txn = db.transaction(store, idbModeReadWrite);
    await txn.objectStore(store).delete(key);
    await txn.completed;
  }

  static Future<void> deleteAll(String store) async {
    final db = await _database;
    final txn = db.transaction(store, idbModeReadWrite);
    final storeObj = txn.objectStore(store);
    await storeObj.clear();
    await txn.completed;
  }

  // ---------- Key/Value عام ----------
  static Future<Object?> kvGet(String key) => get('kv', key);

  static Future<void> kvPut(String key, Object value) =>
      put('kv', {'key': key, 'value': value});

  static Future<Object?> kvGetValue(String key) async {
    final row = await kvGet(key);
    if (row is Map) return row['value'];
    return null;
  }

  static Future<void> kvDelete(String key) => delete('kv', key);

  // ---------- ملفات ----------
  /// id = اسم الملف.
  static Future<void> saveFileMeta(Map<String, dynamic> meta) =>
      put('files', meta);

  static Future<List<Map<String, dynamic>>> listFiles() async {
    final rows = await getAll('files');
    return rows.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  static Future<void> saveFileBlob(String id, Uint8ListBytes bytes) =>
      put('blobs', {'id': id, 'bytes': bytes.bytes, 'filename': bytes.filename});

  static Future<Uint8ListBytes?> fileBlob(String id) async {
    final row = await get('blobs', id);
    if (row is! Map || row['bytes'] == null) return null;
    final raw = row['bytes'];
    List<int>? list;
    if (raw is Uint8List) {
      list = raw;
    } else if (raw is List) {
      list = List<int>.from(raw);
    }
    if (list == null) return null;
    return Uint8ListBytes(list, (row['filename'] ?? '').toString());
  }

  static Future<void> deleteFile(String id) async {
    await delete('files', id);
    await delete('blobs', id);
  }

  static Future<void> clearFiles() async {
    await deleteAll('files');
    await deleteAll('blobs');
    await deleteAll('chunks');
  }

  // ---------- شرائح البحث (chunks) ----------
  static Future<void> saveChunk(Map<String, dynamic> chunk) =>
      put('chunks', chunk);

  static Future<List<Map<String, dynamic>>> allChunks() async {
    final rows = await getAll('chunks');
    return rows.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  static Future<void> clearChunksForFile(String filename) async {
    final all = await allChunks();
    for (final c in all) {
      if (c['file'] == filename) {
        await delete('chunks', c['id']);
      }
    }
  }
}
