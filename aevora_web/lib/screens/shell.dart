import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../client/client_auth.dart';
import '../client/client_sync.dart';
import '../config.dart';
import 'chat_screen.dart';
import 'companion_screen.dart';
import 'document_screen.dart';
import 'settings_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _currentIndex = 0;
  KeySettings _keys = const KeySettings();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final keys = await AppStorage.load();
    if (mounted) setState(() => _keys = keys);
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/setup', (_) => false);
  }

  /// رفع أي تعديل معلّق ثم تسجيل الخروج من الحساب (توجّه الواجهة تلقائياً
  /// عبر مراقب الجلسة في main.dart).
  Future<void> _signOutAccount() async {
    await SyncStore.pushNow();
    await signOut();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      ChatScreen(keys: _keys),
      DocumentScreen(keys: _keys),
      CompanionScreen(keys: _keys),
      SettingsScreen(
        keys: _keys,
        onKeysChanged: (k) => setState(() => _keys = k),
        onLogout: _logout,
        onAccountSignOut: _signOutAccount,
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
            icon: Icon(Icons.folder_shared_outlined),
            selectedIcon: Icon(Icons.folder_shared),
            label: 'المستندات',
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology_alt_outlined),
            selectedIcon: Icon(Icons.psychology_alt_rounded),
            label: 'المساعد',
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
