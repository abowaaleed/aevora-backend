import 'dart:io';

Future<String> voiceRecordPath(String ext) async {
  return '${Directory.systemTemp.path}/evora_voice_${DateTime.now().millisecondsSinceEpoch}.$ext';
}

Future<List<int>> readAudioBytes(String path) => File(path).readAsBytes();
