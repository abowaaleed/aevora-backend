import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.isDeveloperModeEnabled, required this.onDeveloperModeChanged});

  final bool isDeveloperModeEnabled;
  final ValueChanged<bool> onDeveloperModeChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _developerModeEnabled = widget.isDeveloperModeEnabled;
  String _selectedVoice = 'ar-SA-HamedNeural';
  double _speed = 1.0;
  double _pitch = 1.0;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _loadingVoiceId;

  static const Color _greenPrimary = Color(0xFF4CAF50);

  final List<Map<String, String>> _voices = [
    {'id': 'ar-SA-HamedNeural', 'name': 'حميد (عربي - رجالي)'},
    {'id': 'ar-SA-ZariyahNeural', 'name': 'زارية (عربي - نسائي)'},
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedVoice = prefs.getString('tts_voice') ?? 'ar-SA-HamedNeural';
      _speed = prefs.getDouble('tts_speed') ?? 1.0;
      _pitch = prefs.getDouble('tts_pitch') ?? 1.0;
    });
  }

  Future<void> _saveVoice(String voiceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tts_voice', voiceId);
    setState(() => _selectedVoice = voiceId);
  }

  Future<void> _saveSliderSetting(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
    setState(() {
      if (key == 'tts_speed') _speed = value;
      if (key == 'tts_pitch') _pitch = value;
    });
  }

  Future<void> _playPreview(String voiceId) async {
    setState(() => _loadingVoiceId = voiceId);
    try {
      final text = "مرحباً! هذا عرض مسبق لصوتي في مستفيد.";
      
      final rateStr = _getRateString(_speed);
      final pitchStr = _getPitchString(_pitch);
      
      final url = '$backendUrl/voice/synthesize?text=${Uri.encodeComponent(text)}&voice=$voiceId&rate=$rateStr&pitch=$pitchStr';
      final res = await http.post(Uri.parse(url));
      
      if (res.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/preview_$voiceId.mp3';
        final file = File(path);
        await file.writeAsBytes(res.bodyBytes);
        await _audioPlayer.play(DeviceFileSource(path));
      }
    } catch (e) {
      debugPrint("Preview error: $e");
    } finally {
      setState(() => _loadingVoiceId = null);
    }
  }

  String _getRateString(double speed) {
    final percent = ((speed - 1.0) * 100).toInt();
    return percent >= 0 ? '+$percent%' : '$percent%';
  }

  String _getPitchString(double pitch) {
    final percent = ((pitch - 1.0) * 50).toInt();
    return percent >= 0 ? '+$percent%' : '$percent%';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'الإعدادات',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text('تخصيص الصوت والإعدادات العامة', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 24),
              
              // General Section
              _buildSectionTitle('عام'),
              const SizedBox(height: 12),
              _buildSettingCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('وضع المطور', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text('عرض معلومات التقنية بعد كل استجابة', style: TextStyle(color: Colors.white60, fontSize: 13)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _developerModeEnabled,
                      activeColor: _greenPrimary,
                      onChanged: (value) async {
                        setState(() => _developerModeEnabled = value);
                        widget.onDeveloperModeChanged(value);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('developer_mode', value);
                      },
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),

              // Voice Quality Controls
              _buildSectionTitle('ضبط الصوت'),
              const SizedBox(height: 12),
              _buildSettingCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.speed_rounded, color: Colors.white38, size: 20),
                        const SizedBox(width: 12),
                        const Text('السرعة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('${_speed.toStringAsFixed(1)}x', style: const TextStyle(color: _greenPrimary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: _speed,
                      min: 0.5,
                      max: 2.0,
                      divisions: 15,
                      activeColor: _greenPrimary,
                      onChanged: (val) => _saveSliderSetting('tts_speed', val),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.height_rounded, color: Colors.white38, size: 20),
                        const SizedBox(width: 12),
                        const Text('النبرة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('${(_pitch * 100).toInt()}%', style: const TextStyle(color: _greenPrimary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: _pitch,
                      min: 0.5,
                      max: 1.5,
                      divisions: 10,
                      activeColor: _greenPrimary,
                      onChanged: (val) => _saveSliderSetting('tts_pitch', val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
              
              // Voice Section
              _buildSectionTitle('الصوت'),
              const SizedBox(height: 12),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _voices.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final voice = _voices[index];
                  final isSelected = _selectedVoice == voice['id'];
                  final isLoading = _loadingVoiceId == voice['id'];
                  
                  return _buildSettingCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    borderColor: isSelected ? _greenPrimary.withOpacity(0.4) : Colors.white12,
                    child: InkWell(
                      onTap: () => _saveVoice(voice['id']!),
                      child: Row(
                        children: [
                          Radio<String>(
                            value: voice['id']!,
                            groupValue: _selectedVoice,
                            onChanged: (val) => _saveVoice(val!),
                            activeColor: _greenPrimary,
                          ),
                          Expanded(
                            child: Text(
                              voice['name']!,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                                  )
                                : const Icon(Icons.play_circle_outline_rounded, color: Colors.white54),
                            onPressed: isLoading ? null : () => _playPreview(voice['id']!),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2),
    );
  }

  Widget _buildSettingCard({required Widget child, EdgeInsets? padding, Color? borderColor}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131A2B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? Colors.white12),
      ),
      child: child,
    );
  }
}
