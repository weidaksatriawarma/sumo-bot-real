import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pages/controller_page.dart';
import '../pages/logs_page.dart';
import '../pages/network_page.dart';
import '../palette.dart';

class RootShell extends StatefulWidget {
  final Palette palette;
  final bool isDark;
  final VoidCallback onToggleTheme;

  const RootShell({
    super.key,
    required this.palette,
    required this.isDark,
    required this.onToggleTheme,
  });

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  Palette get p => widget.palette;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: p.bg,
      body: IndexedStack(
        index: _index,
        children: [
          ControllerPage(
            palette: p,
            isDark: widget.isDark,
            onToggleTheme: widget.onToggleTheme,
          ),
          LogsPage(palette: p),
          NetworkPage(palette: p),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: p.surface,
          border: Border(top: BorderSide(color: p.border, width: 1)),
        ),
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            currentIndex: _index,
            onTap: (i) {
              HapticFeedback.selectionClick();
              setState(() => _index = i);
            },
            backgroundColor: p.surface,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: p.primary,
            unselectedItemColor: p.textMuted,
            selectedLabelStyle: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w500),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.gamepad_rounded),
                label: 'Control',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.terminal_rounded),
                label: 'Logs',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.wifi_rounded),
                label: 'Network',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
