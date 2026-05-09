import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int kEspUdpPort = 4210;
const String kDefaultIp = '192.168.4.1';
const String kBotSsid = 'SumoBot';
const Duration kRepeatInterval = Duration(milliseconds: 100);
const Duration kDistancePollInterval = Duration(milliseconds: 250);
const int kDistanceMaxCm = 200;       // slider/range cap shown in UI
const int kDistanceLockOnCm = 20;     // < this = target locked (red)
const int kDistanceWarningCm = 50;    // < this = warning (amber)

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const SumoApp());
}

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

  const Palette.dark()
      : bg = const Color(0xFF0B0D10),
        surface = const Color(0xFF15181C),
        surfaceAlt = const Color(0xFF0B0D10),
        text = Colors.white,
        textMuted = const Color(0xFF6B7280),
        border = const Color(0x1AFFFFFF),
        primary = const Color(0xFF4ADE80),
        danger = const Color(0xFFEF4444),
        idle = const Color(0xFF6B7280);

  const Palette.light()
      : bg = const Color(0xFFF5F6F8),
        surface = Colors.white,
        surfaceAlt = const Color(0xFFEDEFF2),
        text = const Color(0xFF0B0D10),
        textMuted = const Color(0xFF6B7280),
        border = const Color(0x14000000),
        primary = const Color(0xFF16A34A),
        danger = const Color(0xFFDC2626),
        idle = const Color(0xFF9CA3AF);
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
      home: ControllerPage(
        palette: palette,
        isDark: _isDark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

class ControllerPage extends StatefulWidget {
  final Palette palette;
  final bool isDark;
  final VoidCallback onToggleTheme;

  const ControllerPage({
    super.key,
    required this.palette,
    required this.isDark,
    required this.onToggleTheme,
  });

  @override
  State<ControllerPage> createState() => _ControllerPageState();
}

class _ControllerPageState extends State<ControllerPage> {
  final TextEditingController _ipCtrl = TextEditingController();
  String? _ip;
  String _status = 'Disconnected';
  String? _activeCmd;
  int _speed = 200;
  int? _distanceCm;
  DateTime? _lastDistanceAt;
  int? _pwmFreqHz;
  int _pwmRes = 8;
  int _pwmMax = 255;

  RawDatagramSocket? _socket;
  InternetAddress? _addr;
  Timer? _repeatTimer;
  Timer? _pingTimer;
  Timer? _distanceTimer;
  DateTime? _lastPong;

  Palette get p => widget.palette;

  Color get _statusColor {
    switch (_status) {
      case 'Connected':
        return p.primary;
      case 'Connecting...':
      case 'Searching...':
        return const Color(0xFFF59E0B);
      case 'No response':
      case 'Invalid IP':
        return p.danger;
      default:
        return p.idle;
    }
  }

  @override
  void initState() {
    super.initState();
    _initSocket();
    _loadIp();
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    _pingTimer?.cancel();
    _distanceTimer?.cancel();
    _socket?.close();
    super.dispose();
  }

  Future<InternetAddress> _pickBindAddress() async {
    // Prefer the 192.168.4.x interface (SumoBot WiFi subnet) so packets
    // route through WiFi and not mobile data.
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          if (addr.address.startsWith('192.168.4.')) return addr;
        }
      }
    } catch (_) {}
    return InternetAddress.anyIPv4;
  }

  Future<void> _initSocket() async {
    try {
      _socket?.close();
      final bindAddr = await _pickBindAddress();
      _socket = await RawDatagramSocket.bind(bindAddr, 0);
      _socket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final dg = _socket!.receive();
          if (dg == null) return;
          final msg = utf8.decode(dg.data, allowMalformed: true).trim();
          if (msg == 'pong' || msg == 'ok' || msg.startsWith('spd:')) {
            _lastPong = DateTime.now();
            if (_status != 'Connected') {
              setState(() => _status = 'Connected');
            }
          } else if (msg.startsWith('dist:')) {
            _lastPong = DateTime.now();
            final raw = int.tryParse(msg.substring(5));
            if (mounted) {
              setState(() {
                _distanceCm = (raw == null || raw < 0) ? null : raw;
                _lastDistanceAt = DateTime.now();
                if (_status != 'Connected') _status = 'Connected';
              });
            }
          } else if (msg.startsWith('info:')) {
            _lastPong = DateTime.now();
            // info:freq=20000,duty=200,res=8,max=255
            final body = msg.substring(5);
            final fields = <String, String>{};
            for (final kv in body.split(',')) {
              final i = kv.indexOf('=');
              if (i > 0) fields[kv.substring(0, i)] = kv.substring(i + 1);
            }
            final freq = int.tryParse(fields['freq'] ?? '');
            final res = int.tryParse(fields['res'] ?? '');
            final maxv = int.tryParse(fields['max'] ?? '');
            if (mounted) {
              setState(() {
                if (freq != null) _pwmFreqHz = freq;
                if (res != null) _pwmRes = res;
                if (maxv != null) _pwmMax = maxv;
                if (_status != 'Connected') _status = 'Connected';
              });
            }
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _loadIp() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('esp_ip') ?? kDefaultIp;
    final savedSpeed = prefs.getInt('speed') ?? 200;
    setState(() {
      _ip = saved;
      _ipCtrl.text = saved;
      _speed = savedSpeed.clamp(0, 255);
    });
    _connect();
  }

  Future<void> _setSpeed(int value) async {
    _sendRaw('spd:$value');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('speed', value);
  }

  Future<void> _saveIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('esp_ip', ip);
    setState(() => _ip = ip);
    _connect();
  }

  Future<void> _connect() async {
    if (_ip == null) return;
    setState(() => _status = 'Searching...');
    try {
      _addr = InternetAddress(_ip!);
      await _initSocket();
      _lastPong = null;
      _sendRaw('ping');
      _sendRaw('spd:$_speed');
      _sendRaw('info');
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _sendRaw('ping');
        final last = _lastPong;
        if (last == null ||
            DateTime.now().difference(last) > const Duration(seconds: 5)) {
          if (_status == 'Connected') {
            setState(() => _status = 'No response');
          } else if (_status != 'No response') {
            setState(() => _status = 'No response');
          }
        }
      });
      _distanceTimer?.cancel();
      _distanceTimer = Timer.periodic(kDistancePollInterval, (_) {
        _sendRaw('dist');
        // If no fresh distance reading in 1.5s, mark as unknown
        final last = _lastDistanceAt;
        if (last != null &&
            DateTime.now().difference(last) > const Duration(milliseconds: 1500)) {
          if (_distanceCm != null && mounted) {
            setState(() => _distanceCm = null);
          }
        }
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (_lastPong == null && mounted) {
          setState(() => _status = 'No response');
        }
      });
    } catch (_) {
      setState(() => _status = 'Invalid IP');
    }
  }

  void _sendRaw(String cmd) {
    final sock = _socket;
    final addr = _addr;
    if (sock == null || addr == null) return;
    try {
      sock.send(utf8.encode(cmd), addr, kEspUdpPort);
    } catch (_) {}
  }

  void _onPressDown(String cmd) {
    HapticFeedback.lightImpact();
    setState(() => _activeCmd = cmd);
    _sendRaw(cmd);
    _repeatTimer?.cancel();
    _repeatTimer = Timer.periodic(kRepeatInterval, (_) => _sendRaw(cmd));
  }

  void _onPressUp() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    setState(() => _activeCmd = null);
    _sendRaw('stop');
    Future.delayed(const Duration(milliseconds: 50), () => _sendRaw('stop'));
  }

  void _openIpSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: p.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: p.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Bot IP Address',
                style: TextStyle(
                    color: p.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Connect phone WiFi to "$kBotSsid" first',
                style: TextStyle(color: p.textMuted, fontSize: 13)),
            const SizedBox(height: 20),
            TextField(
              controller: _ipCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(fontSize: 18, color: p.text),
              decoration: InputDecoration(
                hintText: kDefaultIp,
                hintStyle: TextStyle(color: p.textMuted),
                filled: true,
                fillColor: p.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 16),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  final ip = _ipCtrl.text.trim();
                  if (ip.isNotEmpty) {
                    _saveIp(ip);
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Connect',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildDistanceCard(),
              const SizedBox(height: 16),
              Expanded(child: Center(child: _buildDPad())),
              const SizedBox(height: 16),
              _buildSpeedSlider(),
              const SizedBox(height: 12),
              _buildFooter(),
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
              Text('Sumobot',
                  style: TextStyle(
                      color: p.text,
                      fontSize: 28,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_status,
                      style: TextStyle(
                          color: _statusColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                  if (_ip != null) ...[
                    const SizedBox(width: 8),
                    Text('• $_ip',
                        style: TextStyle(
                            color: p.textMuted, fontSize: 13)),
                  ]
                ],
              ),
            ],
          ),
        ),
        _iconBtn(
          widget.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          widget.onToggleTheme,
        ),
        const SizedBox(width: 8),
        _iconBtn(Icons.refresh_rounded, _connect),
        const SizedBox(width: 8),
        _iconBtn(Icons.settings_outlined, _openIpSheet),
      ],
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(icon, color: p.text.withValues(alpha: 0.75), size: 22),
        ),
      ),
    );
  }

  Widget _buildDPad() {
    const double btnSize = 88;
    const double gap = 14;
    return SizedBox(
      width: btnSize * 3 + gap * 2,
      height: btnSize * 3 + gap * 2,
      child: Stack(
        children: [
          Positioned(
            top: 0, left: btnSize + gap,
            child: _dirBtn('maju', Icons.keyboard_arrow_up_rounded, btnSize),
          ),
          Positioned(
            bottom: 0, left: btnSize + gap,
            child: _dirBtn('mundur', Icons.keyboard_arrow_down_rounded, btnSize),
          ),
          Positioned(
            top: btnSize + gap, left: 0,
            child: _dirBtn('kiri', Icons.keyboard_arrow_left_rounded, btnSize),
          ),
          Positioned(
            top: btnSize + gap, right: 0,
            child: _dirBtn('kanan', Icons.keyboard_arrow_right_rounded, btnSize),
          ),
          Positioned(
            top: btnSize + gap, left: btnSize + gap,
            child: _stopBtn(btnSize),
          ),
        ],
      ),
    );
  }

  Widget _dirBtn(String cmd, IconData icon, double size) {
    final active = _activeCmd == cmd;
    return Listener(
      onPointerDown: (_) => _onPressDown(cmd),
      onPointerUp: (_) => _onPressUp(),
      onPointerCancel: (_) => _onPressUp(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: active ? p.primary : p.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: active ? p.primary : p.border,
            width: 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: p.primary.withValues(alpha: 0.35),
                    blurRadius: 24,
                    spreadRadius: 1,
                  )
                ]
              : [],
        ),
        child: Icon(
          icon,
          size: 44,
          color: active ? Colors.white : p.text,
        ),
      ),
    );
  }

  Widget _stopBtn(double size) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        _repeatTimer?.cancel();
        _sendRaw('stop');
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: p.danger,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: p.danger.withValues(alpha: 0.3),
              blurRadius: 18,
              spreadRadius: 1,
            )
          ],
        ),
        alignment: Alignment.center,
        child: const Text(
          'STOP',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 16,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  Color _distanceColor() {
    final d = _distanceCm;
    if (d == null) return p.idle;
    if (d <= kDistanceLockOnCm) return p.danger;
    if (d <= kDistanceWarningCm) return const Color(0xFFF59E0B);
    return p.primary;
  }

  String _distanceLabel() {
    final d = _distanceCm;
    if (d == null) return 'NO ECHO';
    if (d <= kDistanceLockOnCm) return 'LOCK-ON';
    if (d <= kDistanceWarningCm) return 'TARGET';
    return 'CLEAR';
  }

  Widget _buildDistanceCard() {
    final d = _distanceCm;
    final color = _distanceColor();
    final fillRatio = d == null
        ? 0.0
        : (1.0 - (d.clamp(0, kDistanceMaxCm) / kDistanceMaxCm)).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: d != null && d <= kDistanceLockOnCm
              ? p.danger.withValues(alpha: 0.6)
              : p.border,
          width: 1,
        ),
        boxShadow: d != null && d <= kDistanceLockOnCm
            ? [
                BoxShadow(
                  color: p.danger.withValues(alpha: 0.25),
                  blurRadius: 18,
                  spreadRadius: 1,
                )
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.radar_rounded, color: color, size: 20),
              const SizedBox(width: 10),
              Text('RADAR',
                  style: TextStyle(
                      color: p.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _distanceLabel(),
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                d == null ? '--' : '$d',
                style: TextStyle(
                  color: p.text,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('cm',
                    style: TextStyle(
                        color: p.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  d == null ? 'out of range' : '${kDistanceMaxCm}cm max',
                  style: TextStyle(color: p.textMuted, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(height: 6, color: p.surfaceAlt),
                AnimatedFractionallySizedBox(
                  duration: const Duration(milliseconds: 180),
                  widthFactor: fillRatio,
                  child: Container(height: 6, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatFreq(int? hz) {
    if (hz == null) return '— Hz';
    if (hz >= 1000) {
      final khz = hz / 1000;
      if (khz == khz.roundToDouble()) {
        return '${khz.toInt()} kHz';
      }
      return '${khz.toStringAsFixed(1)} kHz';
    }
    return '$hz Hz';
  }

  Widget _pwmPill(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: p.textMuted),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: p.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 6),
          Text(value,
              style: TextStyle(
                  color: p.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  Widget _buildSpeedSlider() {
    final percent = _pwmMax == 0 ? 0 : ((_speed / _pwmMax) * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: p.primary, size: 18),
              const SizedBox(width: 8),
              Text('PWM SPEED',
                  style: TextStyle(
                      color: p.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
              const Spacer(),
              _pwmPill(Icons.tune_rounded, 'FREQ', _formatFreq(_pwmFreqHz)),
              const SizedBox(width: 6),
              _pwmPill(Icons.straighten_rounded, 'RES', '${_pwmRes}-bit'),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.speed_rounded, color: p.textMuted, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: p.primary,
                    inactiveTrackColor: p.surfaceAlt,
                    thumbColor: p.primary,
                    overlayColor: p.primary.withValues(alpha: 0.2),
                    trackHeight: 4,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 9),
                  ),
                  child: Slider(
                    value: _speed.toDouble().clamp(0, 255),
                    min: 0,
                    max: 255,
                    divisions: 51,
                    onChanged: (v) => setState(() => _speed = v.toInt()),
                    onChangeEnd: (v) {
                      HapticFeedback.selectionClick();
                      _setSpeed(v.toInt());
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 70,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$_speed / $_pwmMax',
                        style: TextStyle(
                            color: p.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                    Text('$percent% duty',
                        style: TextStyle(
                            color: p.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Text(
      _status == 'Invalid IP'
          ? 'Tap settings to enter bot IP'
          : 'Hold a direction • Release to stop',
      textAlign: TextAlign.center,
      style: TextStyle(color: p.textMuted, fontSize: 12),
    );
  }
}
