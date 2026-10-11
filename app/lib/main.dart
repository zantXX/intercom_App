import 'package:flutter/material.dart';
import 'screens/intercom_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IntercomApp());
}

class IntercomApp extends StatelessWidget {
  const IntercomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Intercom P2P',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1F22),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF5865F2), // Discord Blurple
          secondary: Color(0xFF23A55A), // Discord Green
          surface: Color(0xFF2B2D31),
          error: Color(0xFFDA373C),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2B2D31),
          elevation: 0,
        ),
      ),
      home: const IntercomScreen(),
    );
  }
}
