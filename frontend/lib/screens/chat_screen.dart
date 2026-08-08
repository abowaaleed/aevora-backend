import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../config.dart';
import 'document_manager_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  
  bool _isLoading = false;
  
  List<String> _historyKeys = [];
  String _activeSessionId = '';

  late final AnimationController _voicePulseController;

  final ValueNotifier<TextDirection> _textDirection = ValueNotifier<TextDirection>(TextDirection.rtl);
  final ValueNotifier<TextAlign> _textAlign = ValueNotifier<TextAlign>(TextAlign.right);
  final ValueNotifier<bool> _showScrollToBottomButton = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _showNewMessagesPill = ValueNotifier<bool>(false);
  
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  final ValueNotifier<bool> _isVoiceListening = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isVoiceThinking = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isVoiceSpeaking = ValueNotifier<bool>(false);
  final ValueNotifier<String?> _playingMessageId = ValueNotifier<String?>(null);

  static const Color _greenPrimary = Color(0xFF4CAF50);

  ChatMessage _createMessage({required String text, required bool isUser, String? audioPath, String? slowAudioPath, String? id}) {
    final messageId = id ?? '${DateTime.now().microsecondsSinceEpoch}_${text.hashCode}';
    return ChatMessage(
      id: messageId,
      text: text,
      isUser: isUser,
      audioPath: audioPath,
      slowAudioPath: slowAudioPath,
      isPlayingNotifier: _playingMessageId,
      onPlay: _handlePlayMessageAudio,
      onStop: _handleStopAudio,
    );
  }

  String _getRateString(double speed) {
    final percent = ((speed - 1.0) * 100).toInt();
    return percent >= 0 ? '+$percent%' : '$percent%';
  }

  String _getPitchString(double pitch) {
    final percent = ((pitch - 1.0) * 50).toInt();
    return percent >= 0 ? '+$percent%' : '$percent%';
  }

  Future<void> _handlePlayMessageAudio(String id, String text, String? path, {String? rate}) async {
    try {
      await _audioPlayer.stop();
      _playingMessageId.value = id;
      _isVoiceSpeaking.value = true;
      
      if (path != null && !kIsWeb) {
        final file = File(path);
        if (await file.exists()) {
          await _audioPlayer.play(DeviceFileSource(path));
          return;
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final selectedVoice = prefs.getString('tts_voice') ?? 'ar-SA-HamedNeural';
      final speed = prefs.getDouble('tts_speed') ?? 1.0;
      final pitch = prefs.getDouble('tts_pitch') ?? 1.0;
      
      final rateParam = rate != null ? rate : _getRateString(speed);
      final pitchParam = _getPitchString(pitch);
      
      final url = '$backendUrl/voice/synthesize?text=${Uri.encodeComponent(text)}&voice=$selectedVoice&rate=${Uri.encodeComponent(rateParam)}&pitch=${Uri.encodeComponent(pitchParam)}';
      final synthRes = await http.post(Uri.parse(url));
      
      if (synthRes.statusCode == 200) {
        if (kIsWeb) {
          await _audioPlayer.play(BytesSource(synthRes.bodyBytes));
        } else {
          final tempDir = await getTemporaryDirectory();
          final playPath = '${tempDir.path}/mustafeed_replay_${DateTime.now().millisecondsSinceEpoch}_${rate ?? "normal"}.mp3';
          final playFile = File(playPath);
          await playFile.writeAsBytes(synthRes.bodyBytes);
          
          for (int i = 0; i < _messages.length; i++) {
            if (_messages[i].id == id) {
              setState(() {
                final old = _messages[i];
                if (rate == "-25%") {
                  _messages[i] = _createMessage(id: id, text: old.text, isUser: old.isUser, audioPath: old.audioPath, slowAudioPath: playPath);
                } else {
                  _messages[i] = _createMessage(id: id, text: old.text, isUser: old.isUser, audioPath: playPath, slowAudioPath: old.slowAudioPath);
                }
              });
              break;
            }
          }
          await _audioPlayer.play(DeviceFileSource(playPath));
        }
      } else {
        _playingMessageId.value = null;
        _isVoiceSpeaking.value = false;
      }
    } catch (e) {
      _playingMessageId.value = null;
      _isVoiceSpeaking.value = false;
    }
  }

  void _handleStopAudio() {
    _audioPlayer.stop();
    _playingMessageId.value = null;
    _isVoiceSpeaking.value = false;
  }

  Future<void> _toggleVoiceRecording() async {
    if (_isVoiceSpeaking.value) {
      _handleStopAudio();
      await _startListening();
      return;
    }
    if (_isVoiceListening.value) {
      await _stopListeningAndProcess();
      return;
    }
    await _startListening();
  }

  Future<void> _startListening() async {
    try {
      if (!await _audioRecorder.hasPermission()) {
        _showErrorBubble("تم رفض إذن الميكروفون.");
        return;
      }
      
      await _audioPlayer.stop();
      _isVoiceSpeaking.value = false;
      _isVoiceThinking.value = false;
      
      String recordPath = '';
      if (!kIsWeb) {
        final tempDir = await getTemporaryDirectory();
        recordPath = '${tempDir.path}/mustafeed_voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      } else {
        recordPath = 'mustafeed_voice.wav';
      }
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000),
        path: recordPath,
      );
      
      _isVoiceListening.value = true;
    } catch (e) {
      _showErrorBubble("فشل في بدء التسجيل: $e");
    }
  }

  Future<void> _stopListeningAndProcess() async {
    try {
      var path = await _audioRecorder.stop();
      _isVoiceListening.value = false;
      
      if (path == null) {
        _showErrorBubble("لم يتم تسجيل أي صوت.");
        return;
      }

      if (!kIsWeb) {
        if (path.startsWith('file://')) {
          path = Uri.parse(path).toFilePath();
        } else if (path.startsWith('file:')) {
          path = path.substring(5);
        }
      }
      
      _isVoiceThinking.value = true;
      
      List<int> audioBytes;
      if (kIsWeb) {
        final response = await http.get(Uri.parse(path));
        audioBytes = response.bodyBytes;
      } else {
        final file = File(path);
        if (!await file.exists()) {
          _showErrorBubble("ملف الصوت غير موجود.");
          _isVoiceThinking.value = false;
          return;
        }
        audioBytes = await file.readAsBytes();
        try { await file.delete(); } catch (_) {}
      }
      
      if (audioBytes.isEmpty) {
        _showErrorBubble("بيانات الصوت فارغة.");
        _isVoiceThinking.value = false;
        return;
      }
      
      final transcribeUrl = '$backendUrl/voice/transcribe';
      final uploadReq = http.MultipartRequest('POST', Uri.parse(transcribeUrl));
      uploadReq.files.add(http.MultipartFile.fromBytes(
        'file',
        audioBytes,
        filename: 'voice_query.wav',
      ));
      
      final uploadRes = await uploadReq.send();
      if (uploadRes.statusCode != 200) {
        throw Exception("Transcription failed: ${uploadRes.statusCode}");
      }
      
      final resStr = await uploadRes.stream.bytesToString();
      final transcribedText = jsonDecode(resStr)['text']?.toString().trim() ?? '';
      
      if (transcribedText.isEmpty) {
        _showErrorBubble("لم يتم التعرف على الكلام. حاول مرة أخرى.");
        _isVoiceThinking.value = false;
        return;
      }
      
      setState(() {
        _messages.add(_createMessage(text: transcribedText, isUser: true));
        _isLoading = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      await _saveCurrentSession();
      
      await _processChatMessage(transcribedText);
    } catch (e) {
      _showErrorBubble("خطأ في معالجة الصوت: $e");
      _isVoiceThinking.value = false;
      _isVoiceSpeaking.value = false;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _processChatMessage(String message) async {
    final assistantMessageId = '${DateTime.now().microsecondsSinceEpoch}_assistant';
    
    try {
      final client = http.Client();
      final request = http.Request('POST', Uri.parse('$backendUrl/chat/stream'));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'message': message,
        'user_id': 'default_user',
        'session_id': _activeSessionId,
      });

      final response = await client.send(request);
      
      if (response.statusCode == 200) {
        String fullReply = "";
        bool firstChunk = true;

        await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
          if (line.startsWith('data: ')) {
            final dataStr = line.substring(6).trim();
            if (dataStr == '[DONE]') break;
            
            try {
              final data = jsonDecode(dataStr);
              if (data['error'] != null) throw data['error'];
              
              final text = data['text'] ?? "";
              fullReply += text;

              setState(() {
                if (firstChunk) {
                  _messages.add(_createMessage(id: assistantMessageId, text: fullReply, isUser: false));
                  firstChunk = false;
                  _isLoading = false;
                } else {
                  final lastIdx = _messages.indexWhere((m) => m.id == assistantMessageId);
                  if (lastIdx != -1) {
                    _messages[lastIdx] = _createMessage(id: assistantMessageId, text: fullReply, isUser: false);
                  }
                }
              });
              _scrollToBottom();
            } catch (e) {
              debugPrint("Stream parse error: $e");
            }
          }
        }
        await _saveCurrentSession();
        
        // TTS
        await _synthesizeAndPlay(fullReply, assistantMessageId);

      } else {
        setState(() {
          _isLoading = false;
          _messages.add(_createMessage(text: 'خطأ: فشل في الحصول على استجابة (${response.statusCode})', isUser: false));
        });
      }
    } catch (e) {
      debugPrint("Process chat error: $e");
      setState(() {
        _isLoading = false;
        _messages.add(_createMessage(text: 'خطأ: ${e.toString()}', isUser: false));
      });
    }
  }

  Future<void> _synthesizeAndPlay(String replyText, String messageId) async {
    _isVoiceThinking.value = false;
    _isVoiceSpeaking.value = true;
    _playingMessageId.value = messageId;

    final prefs = await SharedPreferences.getInstance();
    final selectedVoice = prefs.getString('tts_voice') ?? 'ar-SA-HamedNeural';
    final speed = prefs.getDouble('tts_speed') ?? 1.0;
    final pitch = prefs.getDouble('tts_pitch') ?? 1.0;
    
    final rateStr = _getRateString(speed);
    final pitchStr = _getPitchString(pitch);
    
    final synthesizeUrl = '$backendUrl/voice/synthesize?text=${Uri.encodeComponent(replyText)}&voice=$selectedVoice&rate=${Uri.encodeComponent(rateStr)}&pitch=${Uri.encodeComponent(pitchStr)}';
    final synthRes = await http.post(Uri.parse(synthesizeUrl));
    
    if (synthRes.statusCode == 200) {
      String? playPath;
      if (kIsWeb) {
        await _audioPlayer.play(BytesSource(synthRes.bodyBytes));
      } else {
        final tempDir = await getTemporaryDirectory();
        playPath = '${tempDir.path}/mustafeed_response_${DateTime.now().millisecondsSinceEpoch}.mp3';
        final playFile = File(playPath);
        await playFile.writeAsBytes(synthRes.bodyBytes);
        await _audioPlayer.play(DeviceFileSource(playPath));
      }

      if (playPath != null && _messages.isNotEmpty) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == messageId);
          if (idx != -1) {
            final old = _messages[idx];
            _messages[idx] = _createMessage(
              id: old.id,
              text: old.text,
              isUser: old.isUser,
              audioPath: playPath,
            );
          }
        });
      }
    } else {
      _isVoiceSpeaking.value = false;
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() {
      _messages.add(_createMessage(text: message, isUser: true));
      _isLoading = true;
      _messageController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    await _saveCurrentSession();

    await _processChatMessage(message);
  }

  void _onMessageTextChanged() {
    final text = _messageController.text;
    final trimmed = text.trimLeft();
    if (trimmed.isEmpty) {
      _textDirection.value = TextDirection.rtl;
      _textAlign.value = TextAlign.right;
      return;
    }
    
    final firstChar = trimmed.substring(0, 1);
    final isArabic = RegExp(r'^[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]').hasMatch(firstChar);
    
    final newDirection = isArabic ? TextDirection.rtl : TextDirection.ltr;
    final newAlign = isArabic ? TextAlign.right : TextAlign.left;
    
    if (_textDirection.value != newDirection) {
      final selection = _messageController.selection;
      _textDirection.value = newDirection;
      _textAlign.value = newAlign;
      _messageController.selection = selection;
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final isAway = (maxScroll - currentScroll) > 200;
    if (_showScrollToBottomButton.value != isAway) {
      _showScrollToBottomButton.value = isAway;
    }
    if (!isAway && _showNewMessagesPill.value) {
      _showNewMessagesPill.value = false;
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 200,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _onNewMessageReceived() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final isCloseToBottom = (maxScroll - currentScroll) < 200;
    if (isCloseToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } else {
      _showNewMessagesPill.value = true;
    }
  }

  @override
  void initState() {
    super.initState();
    _voicePulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    
    _scrollController.addListener(_onScroll);
    _messageController.addListener(_onMessageTextChanged);
    
    _audioPlayer.onPlayerComplete.listen((_) {
      _isVoiceSpeaking.value = false;
      _playingMessageId.value = null;
    });
    
    _initHistory();
  }

  Future<void> _initHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('chat_session_')).toList();
    setState(() => _historyKeys = keys);
    if (keys.isNotEmpty) {
      _loadSession(keys.first);
    } else {
      _startNewChat();
    }
  }

  void _startNewChat() {
    setState(() {
      _messages.clear();
      _activeSessionId = 'chat_session_${DateTime.now().millisecondsSinceEpoch}';
    });
    _seedWelcomeMessage();
    _saveCurrentSession();
  }

  Future<void> _loadSession(String sessionKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(sessionKey);
      if (raw == null) return;
      
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      
      final list = decoded;
      if (mounted) {
        setState(() {
          _messages.clear();
          _activeSessionId = sessionKey;
          for (var item in list) {
            _messages.add(_createMessage(
              text: item['text'] ?? '',
              isUser: item['isUser'] == true,
            ));
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      debugPrint("Error loading session: $e");
    }
  }

  Future<void> _saveCurrentSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _messages.map((m) => {'text': m.text, 'isUser': m.isUser}).toList();
      await prefs.setString(_activeSessionId, jsonEncode(list));
      final keys = prefs.getKeys().where((k) => k.startsWith('chat_session_')).toList();
      if (mounted) {
        setState(() => _historyKeys = keys);
      }
    } catch (e) {
      debugPrint("Error saving session: $e");
    }
  }

  void _seedWelcomeMessage() {
    if (_messages.isNotEmpty) return;
    _messages.add(_createMessage(
      text: 'مرحباً بك في مستفيد! أنا مساعدك الزراعي الذكي.\n\nارفع مستنداتك ثم اسأل عن أي معلومات تريد معرفتها.',
      isUser: false,
    ));
  }

  void _showErrorBubble(String error) {
    setState(() {
      _messages.add(_createMessage(text: error, isUser: false));
    });
    _onNewMessageReceived();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      drawer: Drawer(
        backgroundColor: const Color(0xFF0D1424),
        child: Column(
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF1D3A1D)),
              child: Center(
                child: Text(
                  'مستفيد',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_comment_rounded, color: Color(0xFF81C784)),
              title: const Text('محادثة جديدة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              onTap: () {
                _startNewChat();
                Navigator.of(context).pop();
              },
            ),
            const Divider(color: Colors.white12),
            Expanded(
              child: ListView.builder(
                itemCount: _historyKeys.length,
                itemBuilder: (context, index) {
                  final key = _historyKeys[index];
                  final timestamp = key.split('_').last;
                  final date = DateTime.fromMillisecondsSinceEpoch(int.tryParse(timestamp) ?? 0);
                  final isCurrent = key == _activeSessionId;
                  
                  return ListTile(
                    selected: isCurrent,
                    selectedTileColor: Colors.white12,
                    leading: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white38),
                    title: Text(
                      '${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    onTap: () {
                      _loadSession(key);
                      Navigator.of(context).pop();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070B14),
        elevation: 0,
        centerTitle: false,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _greenPrimary.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.eco_rounded, color: _greenPrimary, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'مستفيد',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'مساعد زراعي ذكي',
                    style: TextStyle(
                      color: Color(0xFF81C784),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_shared_rounded, color: Color(0xFF81C784)),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DocumentManagerScreen()),
              );
            },
            tooltip: 'إدارة المستندات',
          ),
          Builder(
            builder: (context) => IconButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.history_rounded, color: Colors.white54),
              tooltip: 'المحادثات السابقة',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_greenPrimary.withOpacity(0.24), Colors.white.withOpacity(0.04)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _greenPrimary.withOpacity(0.22)),
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مستفيد',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'ارفع مستنداتك واسأل عن أي معلومات',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.eco_rounded, color: _greenPrimary, size: 24),
              ],
            ),
          ),
          
          // Chat area
          Expanded(
            child: Stack(
              children: [
                _messages.isEmpty
                    ? Center(
                        child: Text(
                          'ابدأ بالكتابة أو ارفع مستنداتك أولاً',
                          style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) => _messages[index],
                      ),
                // Floating Scroll Button & New Messages Pill
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _showScrollToBottomButton,
                    builder: (context, showBtn, _) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: _showNewMessagesPill,
                        builder: (context, showPill, _) {
                          if (!showBtn && !showPill) return const SizedBox.shrink();
                          
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showPill)
                                GestureDetector(
                                  onTap: () {
                                    _scrollToBottom();
                                    _showNewMessagesPill.value = false;
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: _greenPrimary,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 14),
                                        SizedBox(width: 6),
                                        Text(
                                          'رسائل جديدة',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (showPill && showBtn) const SizedBox(height: 8),
                              if (showBtn)
                                SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: FloatingActionButton(
                                    heroTag: 'scroll_bottom_btn',
                                    backgroundColor: const Color(0xFF161D2E),
                                    foregroundColor: Colors.white,
                                    elevation: 4,
                                    shape: const CircleBorder(),
                                    onPressed: _scrollToBottom,
                                    child: const Icon(Icons.arrow_downward_rounded, size: 16),
                                  ),
                                ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(color: _greenPrimary),
            ),

          // Voice status bar
          ValueListenableBuilder<bool>(
            valueListenable: _isVoiceListening,
            builder: (context, listening, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: _isVoiceThinking,
                builder: (context, thinking, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: _isVoiceSpeaking,
                    builder: (context, speaking, _) {
                      if (!listening && !thinking && !speaking) return const SizedBox.shrink();
                      
                      Color color = _greenPrimary;
                      String text = '';
                      Widget leadingAnimation;
                      
                      if (listening) {
                        color = Colors.redAccent;
                        text = 'جاري الاستماع...';
                        leadingAnimation = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(5, (index) {
                            return AnimatedBuilder(
                              animation: _voicePulseController,
                              builder: (context, child) {
                                final value = _voicePulseController.value;
                                final heightFactor = (math.sin(value * 2 * math.pi + (index * 0.8)) + 1) / 2;
                                final height = 6.0 + (heightFactor * 14.0);
                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                  width: 2.5,
                                  height: height,
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(1.25),
                                  ),
                                );
                              },
                            );
                          }),
                        );
                      } else if (thinking) {
                        color = Colors.amberAccent;
                        text = 'جاري التفكير...';
                        leadingAnimation = SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                          ),
                        );
                      } else {
                        color = _greenPrimary;
                        text = 'جاري التحدث...';
                        leadingAnimation = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(4, (index) {
                            return AnimatedBuilder(
                              animation: _voicePulseController,
                              builder: (context, child) {
                                final value = _voicePulseController.value;
                                final heightFactor = (math.cos(value * 2 * math.pi + (index * 1.2)) + 1) / 2;
                                final height = 4.0 + (heightFactor * 12.0);
                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                  width: 2.5,
                                  height: height,
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(1.25),
                                  ),
                                );
                              },
                            );
                          }),
                        );
                      }
                      
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        color: color.withOpacity(0.12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            leadingAnimation,
                            const SizedBox(width: 12),
                            Text(
                              text,
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),

          // Message input bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            decoration: const BoxDecoration(color: Color(0xFF070B14)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: KeyboardListener(
                    focusNode: FocusNode(),
                    onKeyEvent: (KeyEvent event) {
                      final isDesktop = Theme.of(context).platform == TargetPlatform.macOS ||
                          Theme.of(context).platform == TargetPlatform.windows ||
                          Theme.of(context).platform == TargetPlatform.linux ||
                          kIsWeb;
                      
                      if (isDesktop && event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                        if (!HardwareKeyboard.instance.isShiftPressed) {
                          _sendMessage();
                        }
                      }
                    },
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 160.0),
                        child: ValueListenableBuilder<TextDirection>(
                          valueListenable: _textDirection,
                          builder: (context, dir, _) {
                            return ValueListenableBuilder<TextAlign>(
                              valueListenable: _textAlign,
                              builder: (context, align, _) {
                                return TextField(
                                  controller: _messageController,
                                  focusNode: _inputFocusNode,
                                  textDirection: dir,
                                  textAlign: align,
                                  maxLines: null,
                                  minLines: 1,
                                  keyboardType: TextInputType.multiline,
                                  textInputAction: TextInputAction.newline,
                                  decoration: InputDecoration(
                                    hintText: 'اكتب سؤالك هنا...',
                                    hintTextDirection: dir,
                                    hintStyle: const TextStyle(color: Colors.white38),
                                    filled: true,
                                    fillColor: const Color(0xFF141A2A),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    suffixIcon: ValueListenableBuilder<bool>(
                                      valueListenable: _isVoiceListening,
                                      builder: (context, listening, _) {
                                        return ValueListenableBuilder<bool>(
                                          valueListenable: _isVoiceSpeaking,
                                          builder: (context, speaking, _) {
                                            return IconButton(
                                              icon: Icon(
                                                listening 
                                                    ? Icons.stop_circle_rounded 
                                                    : (speaking ? Icons.volume_off_rounded : Icons.mic_none_rounded),
                                                color: listening ? Colors.redAccent : Colors.white54,
                                              ),
                                              onPressed: _isLoading ? null : _toggleVoiceRecording,
                                              tooltip: listening ? 'إيقاف التسجيل' : 'سؤال صوتي',
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  decoration: const BoxDecoration(
                    color: _greenPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, color: Colors.white),
                    onPressed: _isLoading ? null : _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _messageController.removeListener(_onMessageTextChanged);
    _textDirection.dispose();
    _textAlign.dispose();
    _showScrollToBottomButton.dispose();
    _showNewMessagesPill.dispose();
    _inputFocusNode.dispose();
    
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _isVoiceListening.dispose();
    _isVoiceThinking.dispose();
    _isVoiceSpeaking.dispose();
    
    _voicePulseController.dispose();
    _messageController.dispose();
    super.dispose();
  }
}

class ChatMessage extends StatefulWidget {
  const ChatMessage({
    super.key,
    required this.id,
    required this.text,
    required this.isUser,
    this.audioPath,
    this.slowAudioPath,
    this.isPlayingNotifier,
    this.onPlay,
    this.onStop,
  });

  final String id;
  final String text;
  final bool isUser;
  final String? audioPath;
  final String? slowAudioPath;
  final ValueNotifier<String?>? isPlayingNotifier;
  final Future<void> Function(String id, String text, String? path, {String? rate})? onPlay;
  final VoidCallback? onStop;

  @override
  State<ChatMessage> createState() => _ChatMessageState();
}

class _ChatMessageState extends State<ChatMessage> {
  bool _isCopied = false;
  bool _isLoadingNormal = false;
  bool _isLoadingSlow = false;

  static const Color _greenPrimary = Color(0xFF4CAF50);

  @override
  void initState() {
    super.initState();
    widget.isPlayingNotifier?.addListener(_updateState);
  }

  @override
  void dispose() {
    widget.isPlayingNotifier?.removeListener(_updateState);
    super.dispose();
  }

  void _updateState() {
    if (mounted) setState(() {});
  }

  bool get _isPlaying => widget.isPlayingNotifier?.value == widget.id;

  Future<void> _handleCopy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _isCopied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _isCopied = false);
    });
  }

  Future<void> _handleAudio({bool slow = false}) async {
    if (_isPlaying) {
      widget.onStop?.call();
    } else {
      if (slow) {
        setState(() => _isLoadingSlow = true);
        await widget.onPlay?.call(widget.id, widget.text, widget.slowAudioPath, rate: "-25%");
        if (mounted) setState(() => _isLoadingSlow = false);
      } else {
        setState(() => _isLoadingNormal = true);
        await widget.onPlay?.call(widget.id, widget.text, widget.audioPath);
        if (mounted) setState(() => _isLoadingNormal = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: widget.isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: widget.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: widget.isUser ? _greenPrimary : const Color(0xFF161D2E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                widget.text,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                top: 4, 
                left: widget.isUser ? 0 : 4,
                right: widget.isUser ? 4 : 0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionButton(
                    icon: _isLoadingNormal
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                          )
                        : Icon(
                            _isPlaying ? Icons.stop : Icons.volume_up,
                            size: 16,
                            color: Colors.white54,
                          ),
                    onPressed: _isLoadingNormal || _isLoadingSlow ? null : () => _handleAudio(slow: false),
                  ),
                  const SizedBox(width: 8),
                  _ActionButton(
                    icon: _isLoadingSlow
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                          )
                        : const Icon(Icons.speed_rounded, size: 16, color: Colors.white54),
                    onPressed: _isLoadingNormal || _isLoadingSlow ? null : () => _handleAudio(slow: true),
                  ),
                  const SizedBox(width: 8),
                  _ActionButton(
                    icon: Icon(
                      _isCopied ? Icons.check : Icons.content_copy,
                      size: 16,
                      color: _isCopied ? _greenPrimary : Colors.white54,
                    ),
                    onPressed: _handleCopy,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, this.onPressed});
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          shape: BoxShape.circle,
        ),
        child: icon,
      ),
    );
  }
}
