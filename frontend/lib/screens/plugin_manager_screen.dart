import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'document_manager_screen.dart';

class PluginManagerScreen extends StatefulWidget {
  const PluginManagerScreen({super.key});

  @override
  State<PluginManagerScreen> createState() => _PluginManagerScreenState();
}

class _PluginManagerScreenState extends State<PluginManagerScreen> with SingleTickerProviderStateMixin {
  List<dynamic> _plugins = [];
  bool _isLoading = false;
  bool _isRecording = false;
  String _voiceTranscriptionResult = '';
  String _ttsInputText = 'Welcome to Aevora plugin and voice portal.';
  
  // Calculator tester fields
  final _calcController = TextEditingController(text: "15 * (4 + 6)");
  String _calcResult = "";

  late final AnimationController _recordAnimController;

  @override
  void initState() {
    super.initState();
    _loadPlugins();
    _recordAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  Future<void> _loadPlugins() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(Uri.parse('$backendUrl/plugins/'));
      if (res.statusCode == 200) {
        setState(() {
          _plugins = jsonDecode(res.body);
        });
      }
    } catch (e) {
      _showSnackbar('Error loading plugins: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testCalculator() async {
    final expr = _calcController.text.trim();
    if (expr.isEmpty) return;

    setState(() => _calcResult = "Executing...");
    try {
      final res = await http.post(
        Uri.parse('$backendUrl/plugins/execute?name=calculator'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"expression": expr}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _calcResult = data['success'] == true
              ? "Result: ${data['result']}"
              : "Error: ${data['error']}";
        });
      } else {
        setState(() => _calcResult = "Execution failed.");
      }
    } catch (e) {
      setState(() => _calcResult = "Error: $e");
    }
  }

  Future<void> _simulateVoiceRecording() async {
    setState(() {
      _isRecording = true;
      _voiceTranscriptionResult = "Recording audio query...";
    });

    // Simulate recording for 2 seconds
    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      _isRecording = false;
      _voiceTranscriptionResult = "Uploading to Voice Engine...";
    });

    try {
      // Send a simulated 100 bytes audio stream
      final request = http.MultipartRequest('POST', Uri.parse('$backendUrl/voice/transcribe'));
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        List<int>.generate(100, (i) => i),
        filename: 'simulated_voice.wav',
      ));

      final response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final data = jsonDecode(responseData);
        setState(() {
          _voiceTranscriptionResult = "Transcribed: \"${data['text']}\"";
        });
      } else {
        setState(() => _voiceTranscriptionResult = "Transcription failed.");
      }
    } catch (e) {
      setState(() => _voiceTranscriptionResult = "Transcription error: $e");
    }
  }

  Future<void> _synthesizeText() async {
    if (_ttsInputText.isEmpty) return;
    _showSnackbar("Synthesizing audio...");
    try {
      final res = await http.post(
        Uri.parse('$backendUrl/voice/synthesize?text=${Uri.encodeComponent(_ttsInputText)}'),
      );
      if (res.statusCode == 200) {
        _showSnackbar("TTS generated successfully! (${res.bodyBytes.length} audio bytes received)");
      } else {
        _showSnackbar("TTS synthesis failed.");
      }
    } catch (e) {
      _showSnackbar("TTS error: $e");
    }
  }

  void _showSnackbar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070B14),
        elevation: 0,
        title: const Text('Plugins & Voice', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Plugins list
                  _buildSectionHeader('Available Plugins', Icons.extension_rounded),
                  const SizedBox(height: 12),
                  _buildPluginsList(),
                  const SizedBox(height: 24),

                  // Calculator tester
                  _buildSectionHeader('Plugin Tester (Calculator)', Icons.calculate_rounded),
                  const SizedBox(height: 12),
                  _buildCalculatorTester(),
                  const SizedBox(height: 24),

                  // Voice testing
                  _buildSectionHeader('Voice Engine Playground', Icons.mic_rounded),
                  const SizedBox(height: 12),
                  _buildVoicePlayground(),
                  const SizedBox(height: 24),

                  // Document RAG
                  _buildSectionHeader('Document RAG (Private Files)', Icons.folder_shared_rounded),
                  const SizedBox(height: 12),
                  _buildDocumentManagerEntry(),
                ],
              ),
            ),
    );
  }

  Widget _buildDocumentManagerEntry() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131A2B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          const Text(
            'Manage and search through your private documents (PDF, Docx, Excel).',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DocumentManagerScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB94DFF),
              minimumSize: const Size.fromHeight(44),
            ),
            icon: const Icon(Icons.settings_system_daydream_rounded, color: Colors.white),
            label: const Text('Open Document Manager', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF8E63F7), size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildPluginsList() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131A2B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: _plugins.map((p) => Card(
          color: const Color(0xFF1C253B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.bolt, color: Color(0xFFF2B84B)),
            title: Text(p['name']?.toString().toUpperCase() ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: Text(p['description'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildCalculatorTester() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131A2B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _calcController,
                  decoration: const InputDecoration(
                    labelText: 'Math Expression',
                    labelStyle: TextStyle(color: Colors.white60),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _testCalculator,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8E63F7)),
                child: const Text('Execute', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _calcResult,
              style: const TextStyle(color: Color(0xFF3DAA7A), fontWeight: FontWeight.w700),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildVoicePlayground() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131A2B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          // STT
          const Align(
            alignment: Alignment.centerLeft,
            child: Text("Speech to Text (STT)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          Center(
            child: AnimatedBuilder(
              animation: _recordAnimController,
              builder: (context, child) {
                return Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _isRecording
                        ? Colors.redAccent.withOpacity(0.2 * _recordAnimController.value + 0.1)
                        : Colors.white12,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    iconSize: 48,
                    icon: Icon(
                      _isRecording ? Icons.fiber_manual_record : Icons.mic,
                      color: _isRecording ? Colors.redAccent : const Color(0xFF8E63F7),
                    ),
                    onPressed: _simulateVoiceRecording,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isRecording ? "Listening..." : "Tap microphone to simulate user voice",
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 10),
          if (_voiceTranscriptionResult.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _voiceTranscriptionResult,
                style: const TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic),
              ),
            ),
          const Divider(color: Colors.white12, height: 30),

          // TTS
          const Align(
            alignment: Alignment.centerLeft,
            child: Text("Text to Speech (TTS)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (val) => _ttsInputText = val,
            controller: TextEditingController(text: _ttsInputText),
            decoration: const InputDecoration(
              labelText: 'Text to speak',
              labelStyle: TextStyle(color: Colors.white60),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _synthesizeText,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8E63F7),
              minimumSize: const Size.fromHeight(44),
            ),
            icon: const Icon(Icons.volume_up, color: Colors.white),
            label: const Text('Synthesize & Speak', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _recordAnimController.dispose();
    _calcController.dispose();
    super.dispose();
  }
}
