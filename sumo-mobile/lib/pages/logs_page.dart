import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../palette.dart';
import '../services/bot_connection.dart';

class LogsPage extends StatefulWidget {
  final Palette palette;
  const LogsPage({super.key, required this.palette});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final BotConnection _bot = BotConnection.instance;
  final Set<LogDirection> _enabled = {
    LogDirection.tx,
    LogDirection.rx,
    LogDirection.system,
    LogDirection.error,
  };

  Palette get p => widget.palette;

  String _formatTs(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)}';
  }

  ({IconData icon, String prefix, Color color}) _styleFor(LogDirection d) {
    switch (d) {
      case LogDirection.tx:
        return (icon: Icons.arrow_upward_rounded, prefix: 'TX', color: p.primary);
      case LogDirection.rx:
        return (icon: Icons.arrow_downward_rounded, prefix: 'RX', color: const Color(0xFF60A5FA));
      case LogDirection.system:
        return (icon: Icons.info_outline_rounded, prefix: 'SYS', color: p.textMuted);
      case LogDirection.error:
        return (icon: Icons.warning_amber_rounded, prefix: 'ERR', color: p.danger);
    }
  }

  Widget _filterChip(LogDirection d, String label) {
    final on = _enabled.contains(d);
    final color = _styleFor(d).color;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          if (on) {
            _enabled.remove(d);
          } else {
            _enabled.add(d);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? color.withValues(alpha: 0.15) : p.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: on ? color.withValues(alpha: 0.6) : p.border,
            width: 1,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                color: on ? color : p.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 12),
              _buildFilterRow(),
              const SizedBox(height: 12),
              Expanded(child: _buildList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Logs',
                  style: TextStyle(
                      color: p.text,
                      fontSize: 26,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              ValueListenableBuilder<List<LogEntry>>(
                valueListenable: _bot.logs,
                builder: (_, logs, __) => Text(
                  '${logs.length} entries • UDP ${kEspUdpPort}',
                  style: TextStyle(color: p.textMuted, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        Material(
          color: p.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              HapticFeedback.mediumImpact();
              _bot.clearLogs();
            },
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              child: Icon(Icons.delete_outline_rounded,
                  color: p.text.withValues(alpha: 0.75), size: 20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        _filterChip(LogDirection.tx, 'TX'),
        const SizedBox(width: 8),
        _filterChip(LogDirection.rx, 'RX'),
        const SizedBox(width: 8),
        _filterChip(LogDirection.system, 'SYS'),
        const SizedBox(width: 8),
        _filterChip(LogDirection.error, 'ERR'),
      ],
    );
  }

  Widget _buildList() {
    return ValueListenableBuilder<List<LogEntry>>(
      valueListenable: _bot.logs,
      builder: (_, logs, __) {
        final filtered =
            logs.where((e) => _enabled.contains(e.dir)).toList(growable: false);

        if (filtered.isEmpty) {
          return Container(
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.border, width: 1),
            ),
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.terminal_rounded,
                      size: 40, color: p.textMuted),
                  const SizedBox(height: 12),
                  Text('No logs yet',
                      style: TextStyle(
                          color: p.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Send a command from the Control tab',
                      style: TextStyle(color: p.textMuted, fontSize: 12)),
                ],
              ),
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.border, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: filtered.length,
              itemBuilder: (_, i) => _buildRow(filtered[i]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRow(LogEntry e) {
    final style = _styleFor(e.dir);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatTs(e.ts),
            style: TextStyle(
              color: p.textMuted,
              fontSize: 11,
              fontFamily: 'monospace',
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 10),
          Icon(style.icon, color: style.color, size: 14),
          const SizedBox(width: 6),
          SizedBox(
            width: 30,
            child: Text(
              style.prefix,
              style: TextStyle(
                color: style.color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              e.content,
              style: TextStyle(
                color: p.text,
                fontSize: 13,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
