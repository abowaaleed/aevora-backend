import 'package:flutter/foundation.dart';

/// تسليم بين الشاشات: فتح تبويب المساعد وبدء رسالة من تنبيه ذكي.
class ChatHandoff {
  ChatHandoff._();

  /// فهرس تبويب الشِل المطلوب (0 مستندات · 1 المساعد · 2 الإعدادات).
  static final ValueNotifier<int?> tabIndex = ValueNotifier<int?>(null);

  /// نص يُرسل تلقائياً في الدردشة عند وصوله.
  static final ValueNotifier<String?> pendingPrompt = ValueNotifier<String?>(null);

  static void openAssistantWith(String prompt) {
    pendingPrompt.value = prompt.trim();
    tabIndex.value = 1;
  }
}
