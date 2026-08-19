Future<String> voiceRecordPath(String ext) async => 'evora_voice.$ext';

Future<List<int>> readAudioBytes(String path) async {
  throw UnsupportedError('web');
}
