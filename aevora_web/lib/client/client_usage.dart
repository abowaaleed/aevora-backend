import 'client_storage.dart';

/// عدّادات الاستهلاك اليومية المحلية.
/// تُحفظ في IndexedDB بمفتاح تاريخ اليوم، فتبقى ثابتة بعد إغلاق المتصفح
/// وتتصفّر تلقائياً عند تغيّر اليوم.
class LocalUsage {
  static const _key = 'usage_today';
  static const geminiLimit = 1500;
  static const groqLimit = 1000;
  static const whisperLimit = 2000;

  static String _today() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  static Future<Map<String, dynamic>> _read() async {
    final row = await LocalDb.kvGetValue(_key);
    if (row is Map) return Map<String, dynamic>.from(row);
    return {'date': _today(), 'gemini': 0, 'groq': 0, 'whisper': 0, 'companion': 0};
  }

  static Future<void> _write(Map<String, dynamic> data) async {
    data['date'] = _today();
    await LocalDb.kvPut(_key, data);
  }

  static Future<Map<String, dynamic>> _bump(String field) async {
    final data = await _read();
    if (data['date'] != _today()) {
      data
        ..clear()
        ..['date'] = _today();
    }
    data[field] = ((data[field] as num?) ?? 0) + 1;
    await _write(data);
    return data;
  }

  static Future<void> recordGemini() => _bump('gemini');
  static Future<void> recordGroq() => _bump('groq');
  static Future<void> recordWhisper() => _bump('whisper');
  static Future<void> recordCompanion() => _bump('companion');

  static Future<Map<String, dynamic>> today() async {
    final data = await _read();
    if (data['date'] != _today()) {
      data
        ..clear()
        ..['date'] = _today();
      await _write(data);
    }
    return {
      'date': data['date'],
      'gemini': {
        'used': data['gemini'] ?? 0,
        'limit': geminiLimit,
        'remaining': geminiLimit - (data['gemini'] ?? 0),
      },
      'groq': {
        'used': data['groq'] ?? 0,
        'limit': groqLimit,
        'remaining': groqLimit - (data['groq'] ?? 0),
      },
      'stt_groq': {
        'used': data['whisper'] ?? 0,
        'limit': whisperLimit,
        'remaining': whisperLimit - (data['whisper'] ?? 0),
      },
      'companion': data['companion'] ?? 0,
    };
  }
}
