import 'package:flutter_test/flutter_test.dart';
import 'package:mustafeed/services/runtime_inspector_service.dart';

void main() {
  test('buildInspectionFromRuntime maps backend runtime metadata into inspector fields', () {
    final service = RuntimeInspectorService();

    final inspection = service.buildInspectionFromRuntime(
      message: 'Help me improve my English',
      selectedMode: 'Quick',
      selectedSkill: 'quick',
      response: 'Here is a polished reply.',
      runtimeData: {
        'selected_mode': 'Quick',
        'selected_skill': 'quick',
        'loaded_memories': ['memory-1'],
        'loaded_personality': 'Friendly coach',
        'loaded_plugins': ['plugin-a'],
        'provider': {
          'name': 'Ollama',
          'model': 'llama3',
          'endpoint': 'http://localhost:11434',
        },
        'prompt_statistics': {
          'prompt_length': 248,
          'system_prompt_length': 120,
          'skill_prompt_length': 40,
          'user_message_length': 24,
          'token_count': 320,
        },
        'stage_timings': [
          {'name': 'Adaptive Analysis', 'status': 'completed', 'duration_ms': 12, 'details': 'Intent detected'},
          {'name': 'Generate Response', 'status': 'completed', 'duration_ms': 156, 'details': 'Provider completed'}
        ],
        'response_duration_ms': 182,
        'token_usage': {'prompt_tokens': 120, 'completion_tokens': 80, 'total_tokens': 200},
      },
    );

    expect(inspection.selectedMode, 'Quick');
    expect(inspection.selectedSkill, 'quick');
    expect(inspection.loadedMemories, ['memory-1']);
    expect(inspection.loadedPersonality, 'Friendly coach');
    expect(inspection.loadedPlugins, ['plugin-a']);
    expect(inspection.aiProvider, 'Ollama (llama3)');
    expect(inspection.responseTimeMs, 182);
    expect(inspection.tokenCount, 200);
    expect(inspection.pipelineStages.length, 2);
    expect(inspection.pipelineStages.first.name, 'Adaptive Analysis');
  });
}
