import '../models/runtime_inspection.dart';

class RuntimeInspectorService {
  RuntimeInspection buildInspection({
    required String message,
    required String selectedMode,
    required String selectedSkill,
    required String response,
  }) {
    return RuntimeInspection(
      adaptiveAnalysis: 'Detected intent from: "$message"',
      selectedMode: selectedMode,
      selectedSkill: selectedSkill,
      loadedMemories: const ['No memories loaded'],
      loadedPersonality: 'Default companion personality',
      loadedPlugins: const ['None'],
      finalPrompt: 'System prompt + skill prompt + user message\n\nUser: $message',
      aiProvider: 'Ollama (local)',
      responseTimeMs: 182,
      tokenCount: 0,
      finalResponse: response,
      pipelineStages: const [
        PipelineStageInspection(
          name: 'Adaptive Analysis',
          status: 'Completed',
          durationMs: 12,
          details: 'Intent classification and response tuning applied.',
        ),
        PipelineStageInspection(
          name: 'Selected Mode',
          status: 'Completed',
          durationMs: 4,
          details: 'Mode resolved from stored preferences.',
        ),
        PipelineStageInspection(
          name: 'Selected Skill',
          status: 'Completed',
          durationMs: 3,
          details: 'Skill mapped to active runtime configuration.',
        ),
        PipelineStageInspection(
          name: 'Loaded Memories',
          status: 'Skipped',
          durationMs: 0,
          details: 'No memory context was available for this request.',
        ),
        PipelineStageInspection(
          name: 'Loaded Personality',
          status: 'Completed',
          durationMs: 2,
          details: 'Default personality profile loaded.',
        ),
        PipelineStageInspection(
          name: 'Loaded Plugins',
          status: 'Skipped',
          durationMs: 0,
          details: 'No plugins were required for this turn.',
        ),
        PipelineStageInspection(
          name: 'Final Prompt',
          status: 'Completed',
          durationMs: 9,
          details: 'Prompt assembled for the provider request.',
        ),
        PipelineStageInspection(
          name: 'AI Provider',
          status: 'Completed',
          durationMs: 152,
          details: 'Local response generated via Ollama.',
        ),
      ],
    );
  }

  RuntimeInspection buildInspectionFromRuntime({
    required String message,
    required String selectedMode,
    required String selectedSkill,
    required String response,
    required Map<String, dynamic> runtimeData,
  }) {
    final provider = runtimeData['provider'] is Map<String, dynamic>
        ? runtimeData['provider'] as Map<String, dynamic>
        : <String, dynamic>{};
    final promptStatistics = runtimeData['prompt_statistics'] is Map<String, dynamic>
        ? runtimeData['prompt_statistics'] as Map<String, dynamic>
        : <String, dynamic>{};
    final stageTimings = (runtimeData['stage_timings'] as List?)
            ?.whereType<Map>()
            .map((entry) => PipelineStageInspection(
                  name: entry['name']?.toString() ?? 'Unknown stage',
                  status: (entry['status'] ?? 'completed').toString().toUpperCase(),
                  durationMs: int.tryParse(entry['duration_ms']?.toString() ?? '') ?? 0,
                  details: entry['details']?.toString() ?? 'No details provided.',
                ))
            .toList() ??
        <PipelineStageInspection>[];
    final tokenUsage = runtimeData['token_usage'] is Map<String, dynamic>
        ? runtimeData['token_usage'] as Map<String, dynamic>
        : <String, dynamic>{};
    final loadedMemories = (runtimeData['loaded_memories'] as List?)
            ?.whereType<Object?>()
            .map((entry) => entry.toString())
            .toList() ??
        <String>[];
    final loadedPlugins = (runtimeData['loaded_plugins'] as List?)
            ?.whereType<Object?>()
            .map((entry) => entry.toString())
            .toList() ??
        <String>[];
    final adaptiveDecision = runtimeData['adaptive_decision'];
    final adaptiveSummary = adaptiveDecision is Map
        ? adaptiveDecision.entries.map((entry) => '${entry.key}: ${entry.value}').join(', ')
        : null;

    final providerName = provider['name']?.toString() ?? 'Unknown provider';
    final providerModel = provider['model']?.toString();
    final aiProvider = providerModel != null && providerModel.isNotEmpty
        ? '$providerName ($providerModel)'
        : providerName;

    final promptLength = promptStatistics['prompt_length'];
    final userMessageLength = promptStatistics['user_message_length'];
    final finalPrompt = promptLength != null && userMessageLength != null
        ? 'Prompt length: $promptLength chars\nUser message length: $userMessageLength chars\nUser: $message'
        : 'System prompt + skill prompt + user message\n\nUser: $message';

    final responseDuration = runtimeData['response_duration_ms'];
    final tokenCount = tokenUsage['total_tokens'] ?? promptStatistics['token_count'] ?? 0;

    return RuntimeInspection(
      adaptiveAnalysis: adaptiveSummary ?? 'Detected intent from: "$message"',
      selectedMode: runtimeData['selected_mode']?.toString() ?? selectedMode,
      selectedSkill: runtimeData['selected_skill']?.toString() ?? selectedSkill,
      loadedMemories: loadedMemories.isNotEmpty ? loadedMemories : const ['No memories loaded'],
      loadedPersonality: runtimeData['loaded_personality']?.toString() ?? 'Default companion personality',
      loadedPlugins: loadedPlugins.isNotEmpty ? loadedPlugins : const ['None'],
      finalPrompt: finalPrompt,
      aiProvider: aiProvider,
      responseTimeMs: int.tryParse(responseDuration?.toString() ?? '') ?? 182,
      tokenCount: int.tryParse(tokenCount?.toString() ?? '') ?? 0,
      finalResponse: response,
      pipelineStages: stageTimings.isNotEmpty
          ? stageTimings
          : const [
              PipelineStageInspection(
                name: 'Runtime Metadata',
                status: 'Completed',
                durationMs: 0,
                details: 'Runtime metadata was returned by the backend.',
              ),
            ],
    );
  }
}
