import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'palette.dart';
import 'services/bot_connection.dart';
import 'widgets/root_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Pre-load persisted state so the first frame already has the saved IP.
  BotConnection.instance.ensureLoaded();
  runApp(const SumoApp());
}

class SumoApp extends StatefulWidget {
  const SumoApp({super.key});

  @override
  State<SumoApp> createState() => _SumoAppState();
}

class _SumoAppState extends State<SumoApp> {
  bool _isDark = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDark = prefs.getBool('is_dark') ?? true;
      _loaded = true;
    });
  }

  Future<void> _toggleTheme() async {
    setState(() => _isDark = !_isDark);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark', _isDark);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const MaterialApp(
        home: Scaffold(backgroundColor: Color(0xFF0B0D10)),
      );
    }
    final palette = _isDark ? const Palette.dark() : const Palette.light();
    return MaterialApp(
      title: 'Sumobot Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: _isDark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: palette.bg,
      ),
      home: RootShell(
        palette: palette,
        isDark: _isDark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}
