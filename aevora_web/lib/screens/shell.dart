import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../client/client_auth.dart';
import '../client/client_handoff.dart';
import '../client/client_sync.dart';
import '../config.dart';
import '../widgets/voice_control_bar.dart';
import 'assistant_screen.dart';
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
    // عند تطبيق بيانات قادمة من الحساب (مفاتيح أُرسلت من جهاز آخر) نعيد
    // تحميل المفاتيح حتى تُحدَّث كل الشاشات.
    SyncStore.onStateApplied = _reloadKeys;
    ChatHandoff.tabIndex.addListener(_onTabRequest);
    _load();
  }

  @override
  void dispose() {
    ChatHandoff.tabIndex.removeListener(_onTabRequest);
    if (SyncStore.onStateApplied == _reloadKeys) {
      SyncStore.onStateApplied = null;
    }
    super.dispose();
  }

  void _onTabRequest() {
    final i = ChatHandoff.tabIndex.value;
    if (i == null || !mounted) return;
    setState(() => _currentIndex = i.clamp(0, 2));
  }

  void _reloadKeys() {
    unawaited(_load());
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
      DocumentScreen(keys: _keys),
      AssistantScreen(keys: _keys),
      SettingsScreen(
        keys: _keys,
        onKeysChanged: (k) => setState(() => _keys = k),
        onLogout: _logout,
        onAccountSignOut: _signOutAccount,
      ),
    ];
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(index: _currentIndex, children: screens),
          ),
          // شريط التحكم بصوت ايفورا: يظهر فوق شريط التنقل أثناء التشغيل
          // على أي تبويب (المساعد أو الإعدادات).
          const VoiceControlBar(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF0D1422),
        indicatorColor: const Color(0xFF1D3A1D),
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_shared_outlined),
            selectedIcon: Icon(Icons.folder_shared),
            label: 'مستندات',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_rounded),
            selectedIcon: Icon(Icons.auto_awesome_rounded),
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
