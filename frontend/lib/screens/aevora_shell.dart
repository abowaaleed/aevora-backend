import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'document_manager_screen.dart';

class AevoraShell extends StatefulWidget {
  const AevoraShell({super.key});

  @override
  State<AevoraShell> createState() => _AevoraShellState();
}

class _AevoraShellState extends State<AevoraShell> {
  int _currentIndex = 0;
  bool _developerModeEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _developerModeEnabled = prefs.getBool('developer_mode') ?? false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const ChatScreen(),
      const DocumentManagerScreen(),
      SettingsScreen(
        isDeveloperModeEnabled: _developerModeEnabled,
        onDeveloperModeChanged: (value) => setState(() => _developerModeEnabled = value),
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF0D1422),
        indicatorColor: const Color(0xFF1D3A1D),
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'سؤال',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_shared_rounded),
            selectedIcon: Icon(Icons.folder_shared),
            label: 'المستندات',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'الإعدادات',
          ),
        ],
      ),
    );
  }
}
