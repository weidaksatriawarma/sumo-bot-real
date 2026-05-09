import 'package:flutter/material.dart';

class Palette {
  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color text;
  final Color textMuted;
  final Color border;
  final Color primary;
  final Color danger;
  final Color idle;
  final Color warning;

  const Palette.dark()
      : bg = const Color(0xFF0B0D10),
        surface = const Color(0xFF15181C),
        surfaceAlt = const Color(0xFF0B0D10),
        text = Colors.white,
        textMuted = const Color(0xFF6B7280),
        border = const Color(0x1AFFFFFF),
        primary = const Color(0xFF4ADE80),
        danger = const Color(0xFFEF4444),
        idle = const Color(0xFF6B7280),
        warning = const Color(0xFFF59E0B);

  const Palette.light()
      : bg = const Color(0xFFF5F6F8),
        surface = Colors.white,
        surfaceAlt = const Color(0xFFEDEFF2),
        text = const Color(0xFF0B0D10),
        textMuted = const Color(0xFF6B7280),
        border = const Color(0x14000000),
        primary = const Color(0xFF16A34A),
        danger = const Color(0xFFDC2626),
        idle = const Color(0xFF9CA3AF),
        warning = const Color(0xFFD97706);
}
