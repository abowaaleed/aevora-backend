import 'package:flutter/material.dart';

class ModeOption {
  const ModeOption({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.description,
    required this.welcomeMessage,
  });

  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final String description;
  final String welcomeMessage;

  static ModeOption quick() {
    return const ModeOption(
      id: 'quick',
      name: 'Quick',
      icon: Icons.flash_on_rounded,
      color: Color(0xFF5B8DEF),
      description: 'Fast answers for everyday questions.',
      welcomeMessage: 'Hello! I am ready to help you quickly.',
    );
  }

  static ModeOption english() {
    return const ModeOption(
      id: 'english',
      name: 'English',
      icon: Icons.language_rounded,
      color: Color(0xFF3DAA7A),
      description: 'Practice and improve your English with guided feedback.',
      welcomeMessage: 'Let us practice English together.',
    );
  }

  static ModeOption programmer() {
    return const ModeOption(
      id: 'programmer',
      name: 'Programmer',
      icon: Icons.code_rounded,
      color: Color(0xFF8E63F7),
      description: 'Get coding help, debugging support, and technical explanations.',
      welcomeMessage: 'I am ready to help you build and debug.',
    );
  }

  static ModeOption think() {
    return const ModeOption(
      id: 'think',
      name: 'Think',
      icon: Icons.psychology_rounded,
      color: Color(0xFFCF6E2E),
      description: 'Work through ideas with deeper reasoning and reflection.',
      welcomeMessage: 'Let us think this through carefully.',
    );
  }

  static ModeOption companion() {
    return const ModeOption(
      id: 'companion',
      name: 'Companion',
      icon: Icons.favorite_rounded,
      color: Color(0xFFE95D7C),
      description: 'Warm and supportive conversations with a personal touch.',
      welcomeMessage: 'I am here with you and ready to chat.',
    );
  }

  static ModeOption fun() {
    return const ModeOption(
      id: 'fun',
      name: 'Fun',
      icon: Icons.celebration_rounded,
      color: Color(0xFFF2B84B),
      description: 'Lighthearted conversations, jokes, and playful ideas.',
      welcomeMessage: 'Let us make this fun and entertaining.',
    );
  }

  static ModeOption research() {
    return const ModeOption(
      id: 'research',
      name: 'Research',
      icon: Icons.search_rounded,
      color: Color(0xFF2F7CE2),
      description: 'Gather structured insight for deeper exploration.',
      welcomeMessage: 'I can help you explore and organize information.',
    );
  }

  static ModeOption travel() {
    return const ModeOption(
      id: 'travel',
      name: 'Travel',
      icon: Icons.flight_takeoff_rounded,
      color: Color(0xFF1F8A70),
      description: 'Plan trips, routes, and travel ideas with ease.',
      welcomeMessage: 'Let us plan your next adventure.',
    );
  }

  static ModeOption coach() {
    return const ModeOption(
      id: 'coach',
      name: 'Coach',
      icon: Icons.sports_rounded,
      color: Color(0xFFB34DC6),
      description: 'Motivation, accountability, and guided progress.',
      welcomeMessage: 'I am here to help you grow and improve.',
    );
  }

  static ModeOption pdf() {
    return const ModeOption(
      id: 'pdf',
      name: 'Document Assistant',
      icon: Icons.picture_as_pdf_rounded,
      color: Color(0xFFB94DFF),
      description: 'Summarize documents, extract key ideas, and ask questions.',
      welcomeMessage: 'I can help you analyze your documents. Please upload a file to get started.',
    );
  }

  static ModeOption general() {
    return const ModeOption(
      id: 'general',
      name: 'عام (General)',
      icon: Icons.auto_awesome_motion_rounded,
      color: Color(0xFF5B8DEF),
      description: 'دردشة شاملة مع أيفورا مع إمكانية الوصول لمستنداتك ومعلوماتك الخاصة.',
      welcomeMessage: 'أهلاً بك! أنا أيفورا، كيف يمكنني مساعدتك اليوم؟ يمكنني الإجابة على أسئلتك العامة أو البحث في مستنداتك.',
    );
  }

  static List<ModeOption> allModes() {
    return [
      general(),
      english(),
      pdf(),
      programmer(),
      think(),
      companion(),
      fun(),
      research(),
      travel(),
      coach(),
    ];
  }
}
