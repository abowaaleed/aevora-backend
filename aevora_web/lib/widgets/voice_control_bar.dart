import 'package:flutter/material.dart';

import '../client/client_voice.dart';

/// شريط التحكم بصوت ايفورا: يظهر أسفل الشاشة أثناء التشغيل ويوفّر
/// إيقافاً مؤقتاً، استئنافاً، وإيقافاً كاملاً — ويعرض سبب تحول النطق
/// إلى صوت المتصفح الأساسي إن حدث.
class VoiceControlBar extends StatelessWidget {
  const VoiceControlBar({super.key});

  static const _green = Color(0xFF4CAF50);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackStatus>(
      valueListenable: PlaybackController.instance.status,
      builder: (context, status, _) {
        final c = PlaybackController.instance;
        if (status == PlaybackStatus.idle) return const SizedBox.shrink();

        final loading = status == PlaybackStatus.loading;
        final paused = status == PlaybackStatus.paused;
        final text = c.currentText.value.trim();

        final label = loading
            ? 'جارٍ توليد صوت ايفورا...'
            : paused
                ? 'صوت ايفورا متوقف مؤقتاً'
                : 'ايفورا تتحدث...';

        return Container(
          key: const ValueKey('voice_control_bar'),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1424),
            border: const Border(top: BorderSide(color: Colors.white12)),
          ),
          child: Row(
            children: [
              Icon(
                paused ? Icons.pause_circle_outline_rounded : Icons.volume_up_rounded,
                color: _green,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (text.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                    ValueListenableBuilder<String?>(
                      valueListenable: c.fallbackNotice,
                      builder: (context, notice, _) {
                        if (notice == null || notice.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded,
                                  size: 12, color: Colors.amberAccent),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  notice,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.amberAccent, fontSize: 10),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _green,
                    ),
                  ),
                )
              else
                IconButton(
                  onPressed: paused ? () => c.resume() : () => c.pause(),
                  icon: Icon(
                    paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    color: Colors.white,
                  ),
                  tooltip: paused ? 'تشغيل' : 'إيقاف مؤقت',
                ),
              IconButton(
                onPressed: c.stop,
                icon: const Icon(Icons.stop_rounded, color: Colors.redAccent),
                tooltip: 'إيقاف كامل',
              ),
            ],
          ),
        );
      },
    );
  }
}
