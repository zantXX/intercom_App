import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/call_controller.dart';
import 'services/discovery_service.dart';
import 'services/storage_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IntercomApp());
}

class IntercomApp extends StatefulWidget {
  const IntercomApp({super.key, this.controller});

  final CallController? controller;

  @override
  State<IntercomApp> createState() => _IntercomAppState();
}

class _IntercomAppState extends State<IntercomApp> {
  CallController? _controller;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller;
    } else {
      _ownsController = true;
      _initDefaultController();
    }
  }

  Future<void> _initDefaultController() async {
    final storage = await StorageService.load();
    if (!mounted) return;
    final discovery = DiscoveryService();
    final ctrl = CallController(storage: storage, discovery: discovery);
    unawaited(ctrl.init());
    setState(() {
      _controller = ctrl;
    });
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    return MaterialApp(
      title: 'Intercom P2P',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1F22),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF5865F2), // Discord Blurple
          secondary: Color(0xFF23A55A), // Discord Green
          surface: Color(0xFF2B2D31),
          error: Color(0xFFED4245),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2B2D31),
          elevation: 0,
        ),
      ),
      home: ctrl == null
          ? const Scaffold(
              backgroundColor: Color(0xFF1E1F22),
              body: Center(child: CircularProgressIndicator()),
            )
          : HomeScreen(controller: ctrl),
    );
  }
}
