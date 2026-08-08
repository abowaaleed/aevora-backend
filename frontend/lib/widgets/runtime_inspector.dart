import 'package:flutter/material.dart';

import '../models/runtime_inspection.dart';

class RuntimeInspector extends StatefulWidget {
  const RuntimeInspector({super.key, required this.inspection});

  final RuntimeInspection inspection;

  @override
  State<RuntimeInspector> createState() => _RuntimeInspectorState();
}

class _RuntimeInspectorState extends State<RuntimeInspector> {
  bool _showPrompt = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101726),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report_outlined, color: Colors.tealAccent, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Runtime Inspector',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${widget.inspection.responseTimeMs}ms',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _InspectorSummaryTile(title: 'Adaptive Analysis', value: widget.inspection.adaptiveAnalysis),
          _InspectorSummaryTile(title: 'Selected Mode', value: widget.inspection.selectedMode),
          _InspectorSummaryTile(title: 'Selected Skill', value: widget.inspection.selectedSkill),
          _InspectorSummaryTile(title: 'Loaded Memories', value: widget.inspection.loadedMemories.join(', ')),
          _InspectorSummaryTile(title: 'Loaded Personality', value: widget.inspection.loadedPersonality),
          _InspectorSummaryTile(title: 'Loaded Plugins', value: widget.inspection.loadedPlugins.join(', ')),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(() => _showPrompt = !_showPrompt),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Text('Final Prompt', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Icon(_showPrompt ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: Colors.white70),
                ],
              ),
            ),
          ),
          if (_showPrompt)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(widget.inspection.finalPrompt, style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4)),
            ),
          const SizedBox(height: 12),
          _InspectorSummaryTile(title: 'AI Provider', value: widget.inspection.aiProvider),
          _InspectorSummaryTile(title: 'Token Count', value: '${widget.inspection.tokenCount} (placeholder)'),
          _InspectorSummaryTile(title: 'Final Response', value: widget.inspection.finalResponse),
          const SizedBox(height: 10),
          Text('Pipeline', style: TextStyle(color: Colors.tealAccent[100], fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...widget.inspection.pipelineStages.map((stage) => _PipelineStageTile(stage: stage)).toList(),
        ],
      ),
    );
  }
}

class _InspectorSummaryTile extends StatelessWidget {
  const _InspectorSummaryTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12))),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13), maxLines: 3, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _PipelineStageTile extends StatelessWidget {
  const _PipelineStageTile({required this.stage});

  final PipelineStageInspection stage;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(stage.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${stage.durationMs}ms', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text(stage.status, style: const TextStyle(color: Colors.tealAccent, fontSize: 12)),
          const SizedBox(height: 4),
          Text(stage.details, style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35)),
        ],
      ),
    );
  }
}
