import 'package:flutter/material.dart';

import 'config.dart';
import 'screens/key_setup_screen.dart';
import 'screens/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final keys = await AppStorage.load();
  runApp(AevoraWebApp(keys: keys));
}

class AevoraWebApp extends StatelessWidget {
  final KeySettings keys;
  const AevoraWebApp({super.key, required this.keys});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
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
      initialRoute: keys.hasKeys ? '/shell' : '/setup',
      routes: {
        '/setup': (_) => const KeySetupScreen(),
        '/shell': (_) => const Shell(),
      },
    );
  }
}
