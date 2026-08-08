import 'package:flutter/material.dart';

class Experience {
  const Experience({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.icon,
    required this.gradientColors,
    required this.launchLabel,
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final IconData icon;
  final List<Color> gradientColors;
  final String launchLabel;

  static List<Experience> allExperiences() {
    return [
      const Experience(
        id: 'general',
        title: 'عام (General)',
        description: 'دردشة شاملة مع الوصول الكامل لمستنداتك ومعلوماتك الخاصة.',
        category: 'الرئيسية',
        icon: Icons.auto_awesome_motion_rounded,
        gradientColors: [Color(0xFF5B8DEF), Color(0xFF2A5CCF)],
        launchLabel: 'فتح الدردشة',
      ),
      const Experience(
        id: 'english',
        title: 'English',
        description: 'Practice grammar, vocabulary, and confidence in real conversations.',
        category: 'Learning',
        icon: Icons.language_rounded,
        gradientColors: [Color(0xFF2FBF8A), Color(0xFF1F7A67)],
        launchLabel: 'Open English',
      ),
      const Experience(
        id: 'coding',
        title: 'Coding',
        description: 'Get coding support, debugging help, and clean implementation ideas.',
        category: 'Productivity',
        icon: Icons.code_rounded,
        gradientColors: [Color(0xFF6F6BFF), Color(0xFF3D3BBF)],
        launchLabel: 'Start Coding',
      ),
      const Experience(
        id: 'news',
        title: 'News',
        description: 'Stay informed with short, digestible updates and summaries.',
        category: 'Daily',
        icon: Icons.newspaper_rounded,
        gradientColors: [Color(0xFFFF8A3D), Color(0xFFCC5A00)],
        launchLabel: 'Open News',
      ),
      const Experience(
        id: 'travel',
        title: 'Travel',
        description: 'Plan trips, routes, packing tips, and destination inspiration.',
        category: 'Lifestyle',
        icon: Icons.flight_takeoff_rounded,
        gradientColors: [Color(0xFF1DA1B5), Color(0xFF176A81)],
        launchLabel: 'Plan Travel',
      ),
      const Experience(
        id: 'pdf',
        title: 'PDF Assistant',
        description: 'Summarize documents, extract key ideas, and ask questions.',
        category: 'Work',
        icon: Icons.picture_as_pdf_rounded,
        gradientColors: [Color(0xFFB94DFF), Color(0xFF7A2EB8)],
        launchLabel: 'Open Assistant',
      ),
      const Experience(
        id: 'study',
        title: 'Study',
        description: 'Turn difficult topics into clear study plans and revision notes.',
        category: 'Learning',
        icon: Icons.auto_stories_rounded,
        gradientColors: [Color(0xFF4DA3FF), Color(0xFF2A6CCF)],
        launchLabel: 'Study Now',
      ),
      const Experience(
        id: 'design',
        title: 'Design',
        description: 'Explore design ideas, layout tips, and visual inspiration.',
        category: 'Creative',
        icon: Icons.palette_rounded,
        gradientColors: [Color(0xFFFF5F8F), Color(0xFFB02457)],
        launchLabel: 'Explore Design',
      ),
      const Experience(
        id: 'fitness',
        title: 'Fitness',
        description: 'Build routines, goals, and healthy habits with guided support.',
        category: 'Wellness',
        icon: Icons.fitness_center_rounded,
        gradientColors: [Color(0xFF31C48D), Color(0xFF13795E)],
        launchLabel: 'Start Fitness',
      ),
      const Experience(
        id: 'recipes',
        title: 'Recipes',
        description: 'Discover meal ideas, ingredients, and simple cooking guidance.',
        category: 'Lifestyle',
        icon: Icons.restaurant_menu_rounded,
        gradientColors: [Color(0xFFFFB547), Color(0xFFB86B00)],
        launchLabel: 'Open Recipes',
      ),
      const Experience(
        id: 'stocks',
        title: 'Stocks',
        description: 'Track market themes, compare ideas, and review financial summaries.',
        category: 'Finance',
        icon: Icons.bar_chart_rounded,
        gradientColors: [Color(0xFF3FA9FF), Color(0xFF005FAD)],
        launchLabel: 'Review Stocks',
      ),
      const Experience(
        id: 'youtube',
        title: 'YouTube',
        description: 'Get summaries, script ideas, and content planning support.',
        category: 'Media',
        icon: Icons.ondemand_video_rounded,
        gradientColors: [Color(0xFFFF4D4F), Color(0xFFB0191B)],
        launchLabel: 'Open Creator Mode',
      ),
      const Experience(
        id: 'instagram',
        title: 'Instagram',
        description: 'Create posts, captions, and smart social content strategy.',
        category: 'Social',
        icon: Icons.camera_alt_rounded,
        gradientColors: [Color(0xFFE84FB8), Color(0xFF8A1E63)],
        launchLabel: 'Open Instagram',
      ),
    ];
  }
}
