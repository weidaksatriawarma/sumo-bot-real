import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../palette.dart';
import '../services/bot_connection.dart';

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
  final BotConnection _bot = BotConnection.instance;

  Palette get p => widget.palette;

  @override
  void initState() {
    super.initState();
    _bot.ensureLoaded().then((_) {
      _ipCtrl.text = _bot.ip;
      if (mounted) _bot.connect(_bot.ip, pushHistory: false);
    });
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  Color _statusColor() {
    switch (_bot.status) {
      case 'Connected':
        return p.primary;
      case 'Connecting...':
      case 'Searching...':
        return p.warning;
      case 'No response':
      case 'Invalid IP':
        return p.danger;
      default:
        return p.idle;
    }
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                    _bot.connect(ip);
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
        bottom: false,
        child: ListenableBuilder(
          listenable: _bot,
          builder: (_, __) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 12),
                _buildDistanceCard(),
                const SizedBox(height: 12),
                Expanded(child: Center(child: _buildDPad())),
                const SizedBox(height: 12),
                _buildSpeedSlider(),
                const SizedBox(height: 4),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final color = _statusColor();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sumobot',
                  style: TextStyle(
                      color: p.text,
                      fontSize: 26,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_bot.status,
                      style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(width: 8),
                  Text('• ${_bot.ip}',
                      style: TextStyle(color: p.textMuted, fontSize: 13)),
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
        _iconBtn(Icons.refresh_rounded, () => _bot.connect(_bot.ip, pushHistory: false)),
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
          width: 42,
          height: 42,
          alignment: Alignment.center,
          child: Icon(icon, color: p.text.withValues(alpha: 0.75), size: 20),
        ),
      ),
    );
  }

  Color _distanceColor() {
    final d = _bot.distanceCm;
    if (d == null) return p.idle;
    if (d <= kDistanceLockOnCm) return p.danger;
    if (d <= kDistanceWarningCm) return p.warning;
    return p.primary;
  }

  String _distanceLabel() {
    final d = _bot.distanceCm;
    if (d == null) return 'NO ECHO';
    if (d <= kDistanceLockOnCm) return 'LOCK-ON';
    if (d <= kDistanceWarningCm) return 'TARGET';
    return 'CLEAR';
  }

  Widget _buildDistanceCard() {
    final d = _bot.distanceCm;
    final color = _distanceColor();
    final fillRatio = d == null
        ? 0.0
        : (1.0 - (d.clamp(0, kDistanceMaxCm) / kDistanceMaxCm))
            .clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              Icon(Icons.radar_rounded, color: color, size: 18),
              const SizedBox(width: 10),
              Text('RADAR',
                  style: TextStyle(
                      color: p.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                d == null ? '--' : '$d',
                style: TextStyle(
                  color: p.text,
                  fontSize: 28,
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
                        fontSize: 13,
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
          const SizedBox(height: 8),
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

  Widget _buildDPad() {
    const double btnSize = 82;
    const double gap = 12;
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
            child: _dirBtn(
                'mundur', Icons.keyboard_arrow_down_rounded, btnSize),
          ),
          Positioned(
            top: btnSize + gap, left: 0,
            child:
                _dirBtn('kiri', Icons.keyboard_arrow_left_rounded, btnSize),
          ),
          Positioned(
            top: btnSize + gap, right: 0,
            child: _dirBtn(
                'kanan', Icons.keyboard_arrow_right_rounded, btnSize),
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
    final active = _bot.activeCmd == cmd;
    return Listener(
      onPointerDown: (_) {
        HapticFeedback.lightImpact();
        _bot.pressDown(cmd);
      },
      onPointerUp: (_) => _bot.pressUp(),
      onPointerCancel: (_) => _bot.pressUp(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: active ? p.primary : p.surface,
          borderRadius: BorderRadius.circular(22),
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
          size: 40,
          color: active ? Colors.white : p.text,
        ),
      ),
    );
  }

  Widget _stopBtn(double size) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        _bot.requestStop();
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: p.danger,
          borderRadius: BorderRadius.circular(22),
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
            fontSize: 15,
            letterSpacing: 1.4,
          ),
        ),
      ),
    );
  }

  String _formatFreq(int? hz) {
    if (hz == null) return '— Hz';
    if (hz >= 1000) {
      final khz = hz / 1000;
      if (khz == khz.roundToDouble()) return '${khz.toInt()} kHz';
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
    final speed = _bot.speed;
    final pwmMax = _bot.pwmMax;
    final percent = pwmMax == 0 ? 0 : ((speed / pwmMax) * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              _pwmPill(Icons.tune_rounded, 'FREQ', _formatFreq(_bot.pwmFreqHz)),
              const SizedBox(width: 6),
              _pwmPill(
                  Icons.straighten_rounded, 'RES', '${_bot.pwmRes}-bit'),
            ],
          ),
          const SizedBox(height: 4),
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
                    value: speed.toDouble().clamp(0, 255),
                    min: 0,
                    max: 255,
                    divisions: 51,
                    onChanged: (v) => _bot.setSpeedLocal(v.toInt()),
                    onChangeEnd: (v) {
                      HapticFeedback.selectionClick();
                      _bot.setSpeed(v.toInt());
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 70,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$speed / $pwmMax',
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
      _bot.status == 'Invalid IP'
          ? 'Tap settings to enter bot IP'
          : 'Hold a direction • Release to stop',
      textAlign: TextAlign.center,
      style: TextStyle(color: p.textMuted, fontSize: 12),
    );
  }
}
