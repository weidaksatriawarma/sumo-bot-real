import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../palette.dart';
import '../services/bot_connection.dart';

class NetworkPage extends StatefulWidget {
  final Palette palette;
  const NetworkPage({super.key, required this.palette});

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  final BotConnection _bot = BotConnection.instance;
  final NetworkInfo _net = NetworkInfo();

  String? _ssid;
  String? _bssid;
  String? _ipv4;
  String? _gateway;
  bool _loading = false;
  bool _permissionDenied = false;
  Timer? _refreshTimer;

  Palette get p => widget.palette;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Refresh every 5s while page is open
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _refresh(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final status = await Permission.location.status;
      if (status.isDenied || status.isRestricted) {
        if (!silent) {
          final result = await Permission.location.request();
          if (result.isDenied || result.isPermanentlyDenied) {
            setState(() {
              _permissionDenied = true;
              _loading = false;
            });
            return;
          }
        }
      }
      _permissionDenied = false;

      final ssid = await _net.getWifiName();
      final bssid = await _net.getWifiBSSID();
      final ipv4 = await _net.getWifiIP();
      final gateway = await _net.getWifiGatewayIP();

      if (!mounted) return;
      setState(() {
        // network_info_plus returns SSID wrapped in quotes on some Android versions
        _ssid = ssid?.replaceAll('"', '');
        _bssid = bssid;
        _ipv4 = ipv4;
        _gateway = gateway;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openAppSettings() => openAppSettings();

  String _statusText() {
    final last = _bot.lastPong;
    if (last == null) return _bot.status;
    final secAgo = DateTime.now().difference(last).inSeconds;
    if (_bot.status == 'Connected') return 'Connected • last reply ${secAgo}s ago';
    return _bot.status;
  }

  Color _statusColor() {
    switch (_bot.status) {
      case 'Connected':
        return p.primary;
      case 'Searching...':
        return p.warning;
      case 'No response':
      case 'Invalid IP':
        return p.danger;
      default:
        return p.idle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: _bot,
          builder: (_, __) => RefreshIndicator(
            color: p.primary,
            backgroundColor: p.surface,
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                _buildPhoneWifiCard(),
                const SizedBox(height: 12),
                _buildBotConnectionCard(),
                const SizedBox(height: 12),
                _buildIpHistoryCard(),
              ],
            ),
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
              Text('Network',
                  style: TextStyle(
                      color: p.text,
                      fontSize: 26,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('WiFi info & connection history',
                  style: TextStyle(color: p.textMuted, fontSize: 13)),
            ],
          ),
        ),
        Material(
          color: p.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              HapticFeedback.lightImpact();
              _refresh();
            },
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              child: _loading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(
                            p.text.withValues(alpha: 0.75)),
                      ),
                    )
                  : Icon(Icons.refresh_rounded,
                      color: p.text.withValues(alpha: 0.75), size: 20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _section(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: p.primary, size: 18),
        const SizedBox(width: 8),
        Text(title.toUpperCase(),
            style: TextStyle(
                color: p.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
      ],
    );
  }

  Widget _row(String label, String? value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(
                    color: p.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(
              value == null || value.isEmpty ? '—' : value,
              style: TextStyle(
                color: valueColor ?? p.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneWifiCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section(Icons.wifi_rounded, 'Phone WiFi'),
          const SizedBox(height: 10),
          if (_permissionDenied)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Location permission required',
                      style: TextStyle(
                          color: p.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                      'Android requires location access to read the WiFi SSID. The app does not record or transmit your location.',
                      style:
                          TextStyle(color: p.textMuted, fontSize: 12)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          await Permission.location.request();
                          _refresh();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: p.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Grant permission'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _openAppSettings,
                        style: TextButton.styleFrom(foregroundColor: p.text),
                        child: const Text('Open settings'),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else ...[
            _row('SSID', _ssid),
            _row('IPv4', _ipv4),
            _row('Gateway', _gateway),
            _row('BSSID', _bssid),
          ],
        ],
      ),
    );
  }

  Widget _buildBotConnectionCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section(Icons.precision_manufacturing_rounded, 'Bot Connection'),
          const SizedBox(height: 10),
          _row('IP', _bot.ip),
          _row('UDP Port', '$kEspUdpPort'),
          _row('Status', _statusText(), valueColor: _statusColor()),
          _row('Speed', '${_bot.speed} / ${_bot.pwmMax}'),
          _row(
              'PWM',
              _bot.pwmFreqHz == null
                  ? '—'
                  : '${_bot.pwmFreqHz} Hz, ${_bot.pwmRes}-bit'),
        ],
      ),
    );
  }

  Widget _buildIpHistoryCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section(Icons.history_rounded, 'Recent Bot IPs'),
          const SizedBox(height: 10),
          ValueListenableBuilder<List<String>>(
            valueListenable: _bot.ipHistory,
            builder: (_, history, __) {
              if (history.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('No connection history yet',
                      style: TextStyle(color: p.textMuted, fontSize: 12)),
                );
              }
              return Column(
                children: history
                    .map((ip) => _historyRow(ip, ip == _bot.ip))
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _historyRow(String ip, bool current) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        HapticFeedback.selectionClick();
        _bot.connect(ip);
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _bot.removeFromIpHistory(ip);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: current ? p.primary : p.idle,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(ip,
                  style: TextStyle(
                      color: p.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace')),
            ),
            if (current)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text('CURRENT',
                    style: TextStyle(
                        color: p.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8)),
              ),
            Icon(Icons.chevron_right_rounded,
                color: p.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}
