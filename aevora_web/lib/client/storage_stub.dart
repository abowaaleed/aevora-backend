import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'blob_types.dart';

/// تنفيذ طبقة التخزين المحلية على منصات الجوال (iOS/Android):
/// البيانات الصغيرة (المحادثات، حالة المساعد، العدّادات) تُحفظ في
/// SharedPreferences وتبقى بعد إغلاق التطبيق، بينما الملفات وشرائح البحث
/// تبقى في الذاكرة لجلسة التشغيل الحالية (وعند تسجيل الدخول تُزامن مع
/// الحساب عبر Firestore).
class LocalDb {
  LocalDb._();

  static const _prefix = 'aevora_kv_';

  static SharedPreferences? _prefs;
  static bool _loaded = false;
  static final Map<String, Object?> _kv = {};
  static final Map<String, Map<String, dynamic>> _files = {};
  static final Map<String, Uint8ListBytes> _blobs = {};
  static final Map<String, Map<String, dynamic>> _chunks = {};

  static Future<void> _ensure() async {
    if (_loaded) return;
    _loaded = true;
    try {
      _prefs = await SharedPreferences.getInstance();
      final p = _prefs;
      if (p == null) return;
      for (final k in p.getKeys()) {
        if (!k.startsWith(_prefix)) continue;
        final raw = p.getString(k);
        if (raw == null) continue;
        try {
          _kv[k.substring(_prefix.length)] = jsonDecode(raw);
        } catch (_) {}
      }
    } catch (_) {
      // غياب المكوّن (مثل بيئة الاختبارات) لا يُسقط التطبيق — نكمل بالذاكرة.
    }
  }

  static Future<void> _persist(String key) async {
    try {
      final v = _kv[key];
      if (v == null) {
        await _prefs?.remove('$_prefix$key');
      } else {
        await _prefs?.setString('$_prefix$key', jsonEncode(v));
      }
    } catch (_) {}
  }

  // ---------- عام ----------
  static Future<void> put(String store, Object value) async {
    await _ensure();
    if (store == 'kv') {
      final row = value is Map ? value : null;
      final key = row?['key']?.toString();
      if (key != null && key.isNotEmpty) {
        _kv[key] = row?['value'];
        await _persist(key);
      }
    } else if (store == 'files') {
      final m = value as Map;
      _files[m['id']?.toString() ?? ''] = Map<String, dynamic>.from(m);
    } else if (store == 'blobs') {
      final m = value as Map;
      _blobs[m['id']?.toString() ?? ''] = Uint8ListBytes(
          List<int>.from(m['bytes'] ?? const []),
          (m['filename'] ?? '').toString());
    } else if (store == 'chunks') {
      final m = value as Map;
      _chunks[m['id']?.toString() ?? ''] = Map<String, dynamic>.from(m);
    }
  }

  static Future<Object?> get(String store, Object key) async {
    await _ensure();
    final k = key.toString();
    if (store == 'kv') {
      if (!_kv.containsKey(k)) return null;
      return {'key': k, 'value': _kv[k]};
    }
    if (store == 'files') return _files[k];
    if (store == 'blobs') {
      final b = _blobs[k];
      if (b == null) return null;
      return {'id': k, 'bytes': b.bytes, 'filename': b.filename};
    }
    if (store == 'chunks') return _chunks[k];
    return null;
  }

  static Future<List<Object>> getAll(String store) async {
    await _ensure();
    if (store == 'files') {
      return _files.values
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    if (store == 'chunks') {
      return _chunks.values
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    if (store == 'blobs') {
      return _blobs.entries
          .map((e) => {
                'id': e.key,
                'bytes': e.value.bytes,
                'filename': e.value.filename,
              })
          .toList();
    }
    return [];
  }

  static Future<void> delete(String store, Object key) async {
    await _ensure();
    final k = key.toString();
    if (store == 'kv') {
      _kv.remove(k);
      await _persist(k);
    } else if (store == 'files') {
      _files.remove(k);
    } else if (store == 'blobs') {
      _blobs.remove(k);
    } else if (store == 'chunks') {
      _chunks.remove(k);
    }
  }

  static Future<void> deleteAll(String store) async {
    await _ensure();
    if (store == 'kv') {
      _kv.clear();
      try {
        final p = _prefs;
        if (p != null) {
          for (final k in p.getKeys().toList()) {
            if (k.startsWith(_prefix)) await p.remove(k);
          }
        }
      } catch (_) {}
    } else if (store == 'files') {
      _files.clear();
    } else if (store == 'blobs') {
      _blobs.clear();
    } else if (store == 'chunks') {
      _chunks.clear();
    }
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
    return rows
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
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
    return rows
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
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
