import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final String id;
  String text;
  final bool isUser;
  _ChatMessage(this.text, this.isUser, {String? id})
      : id = id ?? '${DateTime.now().microsecondsSinceEpoch}_${text.hashCode}';
}

class _ChatScreenState extends State<ChatScreen> {
  static const _green = Color(0xFF4CAF50);

  final TextEditingController _input = TextEditingController();
  final List<_ChatMessage> _messages = [];
  final ScrollController _scroll = ScrollController();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  final ValueNotifier<String?> _playingId = ValueNotifier<String?>(null);

  bool _isLoading = false;
  bool _isListening = false;
  bool _isThinking = false;
  bool _isSpeaking = false;
  bool _audioUnlocked = false;
  String _sessionId = '';

  @override
  void initState() {
    super.initState();
    _sessionId = 'web_session_${DateTime.now().millisecondsSinceEpoch}';
    _messages.add(_ChatMessage(
      'مرحباً بك في ايفورا!\n\nارفع مستنداتك من تبويب «المستندات» ثم اسألني عنها، أو اسألني مباشرة بأي لغة.',
      false,
    ));
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _playingId.value = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _recorder.dispose();
    _player.dispose();
    _playingId.dispose();
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

  /// فتح قناة الصوت عند أول تفاعل (إيماءة) حتى يعمل الرد الصوتي التلقائي
  /// بعد اكتمال البث — المتصفحات تحظر التشغيل خارج إيماءة المستخدم.
  Future<void> _unlockAudio() async {
    if (_audioUnlocked) return;
    try {
      await _player.stop();
      await _player.play(BytesSource(_silentWav()));
      _audioUnlocked = true;
    } catch (_) {
      // الفشل غير حرج — زر السماعة لكل رسالة يعمل دائماً بلمسة مباشرة.
    }
  }

  Uint8List _silentWav() {
    const sampleRate = 8000;
    const dataLen = 800;
    final b = BytesBuilder();
    b.add([0x52, 0x49, 0x46, 0x46]);
    b.add(_le32(36 + dataLen));
    b.add([0x57, 0x41, 0x56, 0x45]);
    b.add([0x66, 0x6d, 0x74, 0x20]);
    b.add(_le32(16));
    b.add(_le16(1));
    b.add(_le16(1));
    b.add(_le32(sampleRate));
    b.add(_le32(sampleRate));
    b.add(_le16(1));
    b.add(_le16(8));
    b.add([0x64, 0x61, 0x74, 0x61]);
    b.add(_le32(dataLen));
    b.add(Uint8List(dataLen));
    return b.toBytes();
  }

  List<int> _le32(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
  List<int> _le16(int v) => [v & 0xff, (v >> 8) & 0xff];

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _isLoading) return;
    await _unlockAudio();
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
      await _speak(reply, messageId: assistant.id);
    } catch (e) {
      assistant.text = 'خطأ: $e';
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _speak(String text, {required String messageId, String? rate}) async {
    if (text.isEmpty) return;
    try {
      if (_playingId.value == messageId) {
        await _player.stop();
        _playingId.value = null;
        setState(() => _isSpeaking = false);
        return;
      }
      await _player.stop();
      _playingId.value = messageId;
      setState(() => _isSpeaking = true);
      final url =
          '$apiBaseUrl/voice/synthesize?text=${Uri.encodeComponent(text)}&voice=ar-SA-HamedNeural&rate=${Uri.encodeComponent(rate ?? '+0%')}&pitch=+0%25';
      final res = await http.post(Uri.parse(url), headers: authHeaders(widget.keys));
      if (res.statusCode == 200) {
        await _player.play(BytesSource(res.bodyBytes));
      } else {
        _playingId.value = null;
        setState(() => _isSpeaking = false);
      }
    } catch (_) {
      _playingId.value = null;
      setState(() => _isSpeaking = false);
    }
  }

  Future<void> _stopPlayback() async {
    await _player.stop();
    _playingId.value = null;
    setState(() => _isSpeaking = false);
  }

  Future<void> _toggleVoice() async {
    await _unlockAudio();
    if (_isSpeaking) {
      await _stopPlayback();
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
              itemBuilder: (context, index) => _MessageBubble(
                message: _messages[index],
                keys: widget.keys,
                playingId: _playingId,
                onSpeak: (id, rate) =>
                    _speak(_messages[index].text, messageId: id, rate: rate),
                onStop: _stopPlayback,
              ),
            ),
          ),
          if (_isThinking)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _green),
                  ),
                  SizedBox(width: 8),
                  Text('جاري تفريغ الصوت...',
                      style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
                ],
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
              backgroundColor: _isListening
                  ? Colors.redAccent
                  : _isThinking
                      ? Colors.amber
                      : const Color(0xFF1D3A1D),
            ),
            icon: Icon(
              _isListening
                  ? Icons.stop_circle_rounded
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

class _MessageBubble extends StatefulWidget {
  final _ChatMessage message;
  final KeySettings keys;
  final ValueNotifier<String?> playingId;
  final Future<void> Function(String id, String? rate) onSpeak;
  final Future<void> Function() onStop;
  const _MessageBubble({
    required this.message,
    required this.keys,
    required this.playingId,
    required this.onSpeak,
    required this.onStop,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  static const _green = Color(0xFF4CAF50);

  bool _copied = false;
  bool _playingNormal = false;
  bool _playingSlow = false;

  @override
  void initState() {
    super.initState();
    widget.playingId.addListener(_onPlayingChanged);
  }

  @override
  void dispose() {
    widget.playingId.removeListener(_onPlayingChanged);
    super.dispose();
  }

  void _onPlayingChanged() {
    if (mounted) setState(() {});
  }

  bool get _isPlaying => widget.playingId.value == widget.message.id;

  Future<void> _copy() async {
    // شارة RLM تُلزم برنامج Word بعرض النص من اليمين إلى اليسار عند اللصق.
    await Clipboard.setData(ClipboardData(text: '\u200F${widget.message.text}'));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _play({bool slow = false}) async {
    if (_isPlaying) {
      setState(() {
        _playingNormal = false;
        _playingSlow = false;
      });
      await widget.onStop();
      return;
    }
    setState(() {
      if (slow) {
        _playingSlow = true;
        _playingNormal = false;
      } else {
        _playingNormal = true;
        _playingSlow = false;
      }
    });
    await widget.onSpeak(widget.message.id, slow ? '-25%' : '+0%');
    if (mounted) {
      setState(() {
        _playingNormal = false;
        _playingSlow = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Align(
        alignment: m.isUser ? Alignment.centerLeft : Alignment.centerRight,
        child: Column(
          crossAxisAlignment: m.isUser ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: const BoxConstraints(maxWidth: 520),
              decoration: BoxDecoration(
                color: m.isUser ? const Color(0xFF1D3A1D) : const Color(0xFF141A2A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                m.text,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, height: 1.6, fontSize: 15),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionButton(
                  icon: _playingNormal
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                        )
                      : Icon(
                          _isPlaying ? Icons.stop_rounded : Icons.volume_up_rounded,
                          size: 16,
                          color: _isPlaying ? _green : Colors.white54,
                        ),
                  onPressed: () => _play(),
                  tooltip: 'استماع',
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: _playingSlow
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                        )
                      : const Icon(Icons.speed_rounded, size: 16, color: Colors.white54),
                  onPressed: () => _play(slow: true),
                  tooltip: 'استماع ببطء',
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icon(
                    _copied ? Icons.check_rounded : Icons.content_copy_rounded,
                    size: 16,
                    color: _copied ? _green : Colors.white54,
                  ),
                  onPressed: _copy,
                  tooltip: 'نسخ',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  const _ActionButton({required this.icon, this.onPressed, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            shape: BoxShape.circle,
          ),
          child: icon,
        ),
      ),
    );
  }
}
