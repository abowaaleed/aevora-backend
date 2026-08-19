import 'package:flutter/material.dart';

import '../config.dart';
import 'chat_screen.dart';

/// تبويب «المساعد»: محادثة ذكية تجيب عن المستندات والأسئلة الشخصية
/// والعامة بفضل ذاكرة ايفورا ومهامه.
class AssistantScreen extends StatefulWidget {
  final KeySettings keys;
  const AssistantScreen({super.key, required this.keys});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  @override
  Widget build(BuildContext context) {
    return ChatScreen(keys: widget.keys);
  }
}
