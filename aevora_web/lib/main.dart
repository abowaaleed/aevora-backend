import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'client/client_auth.dart';
import 'client/client_backup_voice.dart';
import 'client/client_consent.dart';
import 'client/client_plan.dart';
import 'client/client_reminders.dart';
import 'client/client_sync.dart';
import 'config.dart';
import 'screens/key_setup_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notification_content_screen.dart';
import 'screens/shell.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final keys = await AppStorage.load();
  await PlanStore.loadLocal();
  await ConsentStore.loadLocal();
  unawaited(BackupVoice.instance.init());
  try {
    await initFirebase();
    if (isAuthEnabled) {
      await SyncStore.prepare();
      SyncStore.startListening();
      PlanStore.startListening();
      await SyncStore.waitForReady();
    }
  } catch (_) {}
  unawaited(ReminderService.instance.init().then((_) async {
    try {
      final prefs = await ReminderService.instance.load();
      await ReminderService.instance.apply(prefs);
    } catch (_) {}
    final payload = ReminderService.consumePayload();
    if (payload != null && payload.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = appNavigatorKey.currentState;
        if (nav != null) {
          nav.push(MaterialPageRoute(
            builder: (_) => NotificationContentScreen(payload: payload),
          ));
        }
      });
    }
  }));
  runApp(AevoraWebApp(keys: keys));
}

class AevoraWebApp extends StatefulWidget {
  final KeySettings keys;
  const AevoraWebApp({super.key, required this.keys});

  @override
  State<AevoraWebApp> createState() => _AevoraWebAppState();
}

class _AevoraWebAppState extends State<AevoraWebApp> {
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
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            // عند الدخول: انتظار اكتمال أول سحب قبل بناء الشاشات حتى لا
            // تُفتح بعدادات صفر ومستندات مفقودة ثم تُحدَّث يدوياً فقط.
            if (user != null) {
              await SyncStore.waitForReady();
            }
            final nav = appNavigatorKey.currentState;
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
      navigatorKey: appNavigatorKey,
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
        '/notification': (_) => const NotificationContentScreen(),
      },
    );
  }
}
