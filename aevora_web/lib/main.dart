import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'client/client_auth.dart';
import 'client/client_sync.dart';
import 'config.dart';
import 'screens/key_setup_screen.dart';
import 'screens/login_screen.dart';
import 'screens/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final keys = await AppStorage.load();
  try {
    await initFirebase();
    if (isAuthEnabled) {
      // سحب بيانات الحساب قبل عرض الواجهة، ثم ربط تغيّرات الجلسة.
      await SyncStore.prepare();
      SyncStore.startListening();
      await SyncStore.waitForReady();
    }
  } catch (_) {
    // أي فشل في Firebase (الشبكة/التهيئة) لا يُسقط التطبيق؛ نعمل محلياً.
  }
  runApp(AevoraWebApp(keys: keys));
}

class AevoraWebApp extends StatefulWidget {
  final KeySettings keys;
  const AevoraWebApp({super.key, required this.keys});

  @override
  State<AevoraWebApp> createState() => _AevoraWebAppState();
}

class _AevoraWebAppState extends State<AevoraWebApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<User?>? _authSub;
  // تتبّع حالة الجلسة الأخيرة: نوجّه فقط عند تغيُّر حقيقي (دخول/خروج) ونتجاهل
  // أحداث تجديد التوكن التي تصدر من نفس المستخدم، حتى لا تُعاد شاشة التطبيق
  // من جديد وتفقد الرسائل غير المحفوظة.
  String? _lastAuthUid;

  @override
  void initState() {
    super.initState();
    // عند أي تغيّر بالجلسة (دخول/خروج) وجّه تلقائياً بين شاشة الدخول والتطبيق.
    if (isAuthEnabled) {
      _authSub = authStateStream().listen((user) {
        final uid = user?.uid;
        if (uid == _lastAuthUid) return;
        _lastAuthUid = uid;
        // تأجيل التوجيه لما بعد انتهاء إطار البناء الحالي.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            final nav = _navigatorKey.currentState;
            if (nav == null) return;
            nav.pushNamedAndRemoveUntil(
              user != null ? '/shell' : '/login',
              (_) => false,
            );
          } catch (_) {
            // فشل التوجيه لا يُسقط التطبيق.
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  String get _initialRoute {
    if (isAuthEnabled) return isSignedIn ? '/shell' : '/login';
    return widget.keys.hasKeys ? '/shell' : '/setup';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF4CAF50),
          secondary: const Color(0xFF81C784),
          surface: const Color(0xFF0C1220),
          onSurface: Colors.white,
        ).copyWith(surfaceContainerHighest: const Color(0xFF141A2A)),
        scaffoldBackgroundColor: const Color(0xFF070B14),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF070B14),
          elevation: 0,
        ),
        cardColor: const Color(0xFF141A2A),
      ),
      initialRoute: _initialRoute,
      routes: {
        '/login': (_) => const LoginScreen(),
        '/setup': (_) => const KeySetupScreen(),
        '/shell': (_) => const Shell(),
      },
    );
  }
}
