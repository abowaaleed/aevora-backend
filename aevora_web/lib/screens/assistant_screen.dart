import 'package:flutter/material.dart';

import '../config.dart';
import 'chat_screen.dart';
import 'companion_screen.dart';
import 'document_screen.dart';

/// تبويب «المساعد» الموحّد: يجمع المحادثة (الأسئلة والمستندات)،
/// رفع وإدارة المستندات، وصديق ايفورا للتعلّم والدردشة — في قسم واحد
/// حتى لا يتشتت المستخدم بين تبويبات متعددة.
class AssistantScreen extends StatefulWidget {
  final KeySettings keys;
  const AssistantScreen({super.key, required this.keys});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  static const _green = Color(0xFF4CAF50);

  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _segmentedBar(),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              ChatScreen(keys: widget.keys),
              DocumentScreen(keys: widget.keys),
              CompanionScreen(keys: widget.keys),
            ],
          ),
        ),
      ],
    );
  }

  Widget _segmentedBar() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF0D1422),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: _segment(0, Icons.chat_bubble_outline_rounded, 'محادثة'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _segment(1, Icons.folder_shared_outlined, 'مستندات'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _segment(2, Icons.psychology_alt_outlined, 'صديق'),
          ),
        ],
      ),
    );
  }

  Widget _segment(int index, IconData icon, String label) {
    final selected = _tab == index;
    return Material(
      color: selected
          ? const Color(0xFF1D3A1D)
          : Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _tab = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? _green : Colors.white54),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
