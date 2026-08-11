import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

import '../api.dart';
import '../config.dart';

class ChatScreen extends StatefulWidget {
  final KeySettings keys;
  const ChatScreen({super.key, required this.keys});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatMessage {
  String text;
  final bool isUser;
  _ChatMessage(this.text, this.isUser);
}

class _ChatScreenState extends State<ChatScreen> {
  static const _green = Color(0xFF4CAF50);

  final TextEditingController _input = TextEditingController();
  final List<_ChatMessage> _messages = [];
  final ScrollController _scroll = ScrollController();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  bool _isLoading = false;
  bool _isListening = false;
  bool _isThinking = false;
  bool _isSpeaking = false;
  String _sessionId = '';

  @override
  void initState() {
    super.initState();
    _sessionId = 'web_session_${DateTime.now().millisecondsSinceEpoch}';
    _messages.add(_ChatMessage(
      'مرحباً بك في ايفورا ويب!\n\nارفع مستنداتك من تبويب «المستندات» ثم اسألني عنها، أو اسألني مباشرة بأي لغة.',
      false,
    ));
    _player.onPlayerComplete.listen((_) {
      setState(() => _isSpeaking = false);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _isLoading) return;
    setState(() {
      _messages.add(_ChatMessage(text, true));
      _isLoading = true;
      _input.clear();
    });
    _scrollToBottom();

    final assistant = _ChatMessage('', false);
    setState(() => _messages.add(assistant));

    try {
      final reply = await streamChat(
        text,
        _sessionId,
        widget.keys,
        onChunk: (partial) {
          assistant.text += partial;
          if (mounted) setState(() {});
          _scrollToBottom();
        },
      );
      assistant.text = reply;
      if (mounted) setState(() {});
      _scrollToBottom();
      await _speak(reply);
    } catch (e) {
      assistant.text = 'خطأ: $e';
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _speak(String text) async {
    if (text.isEmpty) return;
    try {
      await _player.stop();
      setState(() => _isSpeaking = true);
      final url =
          '$apiBaseUrl/voice/synthesize?text=${Uri.encodeComponent(text)}&voice=ar-SA-HamedNeural&rate=+0%25&pitch=+0%25';
      final res = await http.post(Uri.parse(url), headers: authHeaders(widget.keys));
      if (res.statusCode == 200) {
        await _player.play(BytesSource(res.bodyBytes));
      } else {
        setState(() => _isSpeaking = false);
      }
    } catch (_) {
      setState(() => _isSpeaking = false);
    }
  }

  Future<void> _toggleVoice() async {
    if (_isSpeaking) {
      await _player.stop();
      setState(() => _isSpeaking = false);
    }
    if (_isListening) {
      await _stopAndTranscribe();
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        _addError('تم رفض إذن الميكروفون.');
        return;
      }
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000),
        path: 'evora_voice.wav',
      );
      setState(() => _isListening = true);
    } catch (e) {
      _addError('فشل بدء التسجيل: $e');
    }
  }

  Future<void> _stopAndTranscribe() async {
    try {
      final path = await _recorder.stop();
      setState(() => _isListening = false);
      if (path == null) return;

      setState(() => _isThinking = true);
      final audioBytes = (await http.get(Uri.parse(path))).bodyBytes;

      final uploadReq = http.MultipartRequest(
        'POST',
        Uri.parse('$apiBaseUrl/voice/transcribe'),
      );
      uploadReq.headers.addAll(authHeaders(widget.keys));
      uploadReq.files.add(http.MultipartFile.fromBytes(
        'file',
        audioBytes,
        filename: 'voice_query.wav',
      ));
      final res = await uploadReq.send().timeout(const Duration(minutes: 2));
      final body = await res.stream.bytesToString();
      if (res.statusCode != 200) {
        throw Exception('التعرف على الصوت فشل (${res.statusCode}): $body');
      }
      final text = (jsonDecode(body)['text'] ?? '').toString().trim();
      if (text.isEmpty) {
        _addError('لم يُفهم الكلام. حاول مرة أخرى.');
        return;
      }
      setState(() => _isThinking = false);
      await _send(text);
    } catch (e) {
      setState(() {
        _isThinking = false;
        _isListening = false;
      });
      _addError('خطأ في الصوت: $e');
    }
  }

  void _addError(String msg) {
    if (!mounted) return;
    setState(() => _messages.add(_ChatMessage(msg, false)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final m = _messages[index];
                return Align(
                  alignment: m.isUser ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: const BoxConstraints(maxWidth: 520),
                    decoration: BoxDecoration(
                      color: m.isUser ? const Color(0xFF1D3A1D) : const Color(0xFF141A2A),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      m.text,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.white, height: 1.6, fontSize: 15),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _green),
                  ),
                  SizedBox(width: 8),
                  Text('ايفورا تكتب...',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      color: const Color(0xFF0D1424),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              textDirection: TextDirection.rtl,
              style: const TextStyle(color: Colors.white),
              onSubmitted: _send,
              decoration: InputDecoration(
                hintText: 'اكتب سؤالك...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF141A2A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _isLoading ? null : _toggleVoice,
            style: IconButton.styleFrom(
              backgroundColor: _isListening ? Colors.redAccent : const Color(0xFF1D3A1D),
            ),
            icon: Icon(
              _isListening
                  ? Icons.mic
                  : _isThinking
                      ? Icons.hourglass_top
                      : Icons.mic_none,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _isLoading ? null : () => _send(_input.text),
            style: IconButton.styleFrom(backgroundColor: _green),
            icon: const Icon(Icons.send_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
