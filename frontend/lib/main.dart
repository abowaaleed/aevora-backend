import 'package:flutter/material.dart';

import 'screens/aevora_shell.dart';

void main() async {
  // Ensure Flutter is ready before doing anything else
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint("[CRITICAL] ${details.exception}");
  };

  // Run the app immediately to show the UI
  runApp(const MustafeedApp());
}

class MustafeedApp extends StatelessWidget {
  const MustafeedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مستفيد',
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
      home: const AevoraShell(),
    );
  }
}
