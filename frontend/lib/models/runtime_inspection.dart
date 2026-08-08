class RuntimeInspection {
  const RuntimeInspection({
    required this.adaptiveAnalysis,
    required this.selectedMode,
    required this.selectedSkill,
    required this.loadedMemories,
    required this.loadedPersonality,
    required this.loadedPlugins,
    required this.finalPrompt,
    required this.aiProvider,
    required this.responseTimeMs,
    required this.tokenCount,
    required this.finalResponse,
    required this.pipelineStages,
  });

  final String adaptiveAnalysis;
  final String selectedMode;
  final String selectedSkill;
  final List<String> loadedMemories;
  final String loadedPersonality;
  final List<String> loadedPlugins;
  final String finalPrompt;
  final String aiProvider;
  final int responseTimeMs;
  final int tokenCount;
  final String finalResponse;
  final List<PipelineStageInspection> pipelineStages;
}

class PipelineStageInspection {
  const PipelineStageInspection({
    required this.name,
    required this.status,
    required this.durationMs,
    required this.details,
  });

  final String name;
  final String status;
  final int durationMs;
  final String details;
}
