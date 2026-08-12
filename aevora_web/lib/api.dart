import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

/// إرجاع رؤوس التفويض التي يحتاجها الخادم لتحديد هوية المستخدم
/// (المفتاح هو الهوية — تُحقن المفاتيح فقط داخل طلبات البروكسي ولا تُسجّل).
Map<String, String> authHeaders(KeySettings s) {
  return {
    if (s.geminiKey.isNotEmpty) 'x-gemini-key': s.geminiKey,
    if (s.groqKey.isNotEmpty) 'x-groq-key': s.groqKey,
    if (s.email.isNotEmpty) 'x-user-email': s.email,
    'x-user-id': AppStorage.deriveUserId(s),
  };
}

Future<http.Response> apiGet(String path, KeySettings keys) async {
  return http
      .get(Uri.parse('$apiBaseUrl$path'), headers: authHeaders(keys))
      .timeout(const Duration(minutes: 3));
}

Future<http.Response> apiPost(String path, KeySettings keys,
    {Map<String, dynamic>? body}) async {
  return http
      .post(
        Uri.parse('$apiBaseUrl$path'),
        headers: {...authHeaders(keys), 'Content-Type': 'application/json'},
        body: body != null ? jsonEncode(body) : null,
      )
      .timeout(const Duration(minutes: 3));
}

Future<http.Response> apiDelete(String path, KeySettings keys) async {
  return http
      .delete(Uri.parse('$apiBaseUrl$path'), headers: authHeaders(keys))
      .timeout(const Duration(minutes: 3));
}

/// رفع ملفات بصيغة متعددة الأجزاء مع مفاتيح المستخدم.
Future<http.StreamedResponse> apiUpload(
  String path,
  KeySettings keys,
  List<MapEntry<String, Uint8ListBytes>> files,
) async {
  final req = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl$path'));
  req.headers.addAll(authHeaders(keys));
  for (final f in files) {
    req.files.add(http.MultipartFile.fromBytes(
      f.key,
      f.value.bytes,
      filename: f.value.filename,
    ));
  }
  return req.send().timeout(const Duration(minutes: 10));
}

class Uint8ListBytes {
  final List<int> bytes;
  final String filename;
  const Uint8ListBytes(this.bytes, this.filename);
}

/// إرسال طلب محادثة متدفق (SSE) وإرجاع النص الكامل للرد.
Future<String> streamChat(
  String message,
  String sessionId,
  KeySettings keys, {
  void Function(String partial)? onChunk,
}) async {
  final req = http.Request('POST', Uri.parse('$apiBaseUrl/chat/stream'));
  req.headers.addAll({...authHeaders(keys), 'Content-Type': 'application/json'});
  req.body = jsonEncode({
    'message': message,
    'user_id': AppStorage.deriveUserId(keys),
    'session_id': sessionId,
  });
  final response = await req.send().timeout(const Duration(minutes: 4));

  if (response.statusCode != 200) {
    final body = await response.stream.bytesToString();
    throw Exception('الخادم رفض الطلب (${response.statusCode}): $body');
  }

  var full = '';
  await for (final line
      in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
    if (!line.startsWith('data: ')) continue;
    final dataStr = line.substring(6).trim();
    if (dataStr == '[DONE]') break;
    try {
      final data = jsonDecode(dataStr);
      if (data['error'] != null) throw Exception(data['error']);
      final text = data['text'] ?? '';
      if (text.isNotEmpty) {
        full += text;
        onChunk?.call(text);
      }
    } catch (_) {}
  }
  return full;
}

/// إرسال رسالة للمساعد الشخصي (SSE) وإرجاع الرد كاملاً.
Future<String> streamCompanion(
  String message,
  KeySettings keys, {
  void Function(String partial)? onChunk,
}) async {
  final req = http.Request('POST', Uri.parse('$apiBaseUrl/companion/chat'));
  req.headers.addAll({...authHeaders(keys), 'Content-Type': 'application/json'});
  req.body = jsonEncode({'message': message});
  final response = await req.send().timeout(const Duration(minutes: 4));

  if (response.statusCode != 200) {
    final body = await response.stream.bytesToString();
    throw Exception('الخادم رفض الطلب (${response.statusCode}): $body');
  }

  var full = '';
  await for (final line
      in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
    if (!line.startsWith('data: ')) continue;
    final dataStr = line.substring(6).trim();
    if (dataStr == '[DONE]') break;
    try {
      final data = jsonDecode(dataStr);
      if (data['error'] != null) throw Exception(data['error']);
      final text = data['text'] ?? '';
      if (text.isNotEmpty) {
        full += text;
        onChunk?.call(text);
      }
    } catch (_) {}
  }
  return full;
}

Future<Map<String, dynamic>> companionState(KeySettings keys) async {
  final res = await apiGet('/companion/state', keys);
  if (res.statusCode != 200) {
    throw Exception('فشل جلب حالة المساعد (${res.statusCode}): ${res.body}');
  }
  return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> companionMemory(KeySettings keys) async {
  final res = await apiGet('/companion/memory', keys);
  if (res.statusCode != 200) {
    throw Exception('فشل جلب الذاكرة (${res.statusCode}): ${res.body}');
  }
  return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
}

Future<void> companionAddTask(KeySettings keys, String text, {String? due}) async {
  final res = await apiPost('/companion/tasks', keys,
      body: {'text': text, 'due': ?due});
  if (res.statusCode != 200) {
    throw Exception('فشل إضافة المهمة (${res.statusCode}): ${res.body}');
  }
}

Future<void> companionToggleTask(KeySettings keys, String taskId) async {
  await apiPost('/companion/tasks/$taskId/toggle', keys);
}

Future<void> companionDeleteTask(KeySettings keys, String taskId) async {
  await apiDelete('/companion/tasks/$taskId', keys);
}

Future<void> companionReset(KeySettings keys) async {
  await apiPost('/companion/reset', keys);
}

Future<void> companionAcknowledge(KeySettings keys) async {
  await apiPost('/companion/acknowledge', keys);
}

Future<Map<String, dynamic>> usageState(KeySettings keys) async {
  final res = await apiGet('/usage', keys);
  if (res.statusCode != 200) {
    throw Exception('فشل جلب الاستهلاك (${res.statusCode}): ${res.body}');
  }
  return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
}
