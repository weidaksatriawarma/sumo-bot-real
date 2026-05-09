import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int kEspUdpPort = 4210;
const String kDefaultIp = '192.168.4.1';
const String kBotSsid = 'SumoBot';
const Duration kRepeatInterval = Duration(milliseconds: 100);
const Duration kDistancePollInterval = Duration(milliseconds: 250);
const int kDistanceMaxCm = 200;
const int kDistanceLockOnCm = 20;
const int kDistanceWarningCm = 50;
const int kMaxLogEntries = 200;
const int kMaxIpHistory = 5;

enum LogDirection { tx, rx, system, error }

class LogEntry {
  final DateTime ts;
  final LogDirection dir;
  final String content;
  final String? from;
  LogEntry(this.dir, this.content, {this.from}) : ts = DateTime.now();
}

/// Singleton owning the UDP socket, command/reply state, log buffer,
/// and persisted IP history. UI widgets read via getters and subscribe
/// via [ChangeNotifier] (or [logs] / [ipHistory] for fine-grained
/// rebuilds).
class BotConnection extends ChangeNotifier {
  BotConnection._();
  static final BotConnection instance = BotConnection._();

  // --- Connection ---
  String _ip = kDefaultIp;
  String get ip => _ip;
  String _status = 'Disconnected';
  String get status => _status;
  DateTime? _lastPong;
  DateTime? get lastPong => _lastPong;

  RawDatagramSocket? _socket;
  InternetAddress? _addr;
  Timer? _pingTimer;
  Timer? _distanceTimer;
  Timer? _repeatTimer;

  // --- Active D-Pad command ---
  String? _activeCmd;
  String? get activeCmd => _activeCmd;

  // --- PWM / Speed ---
  int _speed = 200;
  int get speed => _speed;
  int? _pwmFreqHz;
  int? get pwmFreqHz => _pwmFreqHz;
  int _pwmRes = 8;
  int get pwmRes => _pwmRes;
  int _pwmMax = 255;
  int get pwmMax => _pwmMax;

  // --- Distance (HC-SR04) ---
  int? _distanceCm;
  int? get distanceCm => _distanceCm;
  DateTime? _lastDistanceAt;

  // --- Logs ---
  final ValueNotifier<List<LogEntry>> logs = ValueNotifier(<LogEntry>[]);
  void _appendLog(LogEntry entry) {
    final next = <LogEntry>[entry, ...logs.value];
    if (next.length > kMaxLogEntries) {
      next.removeRange(kMaxLogEntries, next.length);
    }
    logs.value = next;
  }

  void clearLogs() {
    logs.value = const <LogEntry>[];
  }

  // --- IP history ---
  final ValueNotifier<List<String>> ipHistory = ValueNotifier(<String>[]);

  Future<void> _saveIpHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('ip_history', ipHistory.value);
  }

  Future<void> _pushIpHistory(String ip) async {
    final cleaned = ip.trim();
    if (cleaned.isEmpty) return;
    final next = [cleaned, ...ipHistory.value.where((e) => e != cleaned)];
    if (next.length > kMaxIpHistory) {
      next.removeRange(kMaxIpHistory, next.length);
    }
    ipHistory.value = next;
    await _saveIpHistory();
  }

  Future<void> removeFromIpHistory(String ip) async {
    ipHistory.value =
        ipHistory.value.where((e) => e != ip).toList(growable: false);
    await _saveIpHistory();
  }

  // --- Init / load persisted state ---
  bool _loaded = false;
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _ip = prefs.getString('esp_ip') ?? kDefaultIp;
    _speed = (prefs.getInt('speed') ?? 200).clamp(0, 255);
    ipHistory.value = prefs.getStringList('ip_history') ?? <String>[];
    _appendLog(LogEntry(LogDirection.system, 'App started'));
    notifyListeners();
  }

  // --- Status helpers ---
  void _setStatus(String s) {
    if (_status == s) return;
    _status = s;
    _appendLog(LogEntry(LogDirection.system, s));
    notifyListeners();
  }

  // --- Socket lifecycle ---
  Future<InternetAddress> _pickBindAddress() async {
    try {
      final ifaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
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
      _socket!.listen(_onSocketEvent);
    } catch (e) {
      _appendLog(LogEntry(LogDirection.error, 'Socket bind failed: $e'));
    }
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;
    final msg = utf8.decode(dg.data, allowMalformed: true).trim();
    final from = dg.address.address;
    _appendLog(LogEntry(LogDirection.rx, msg, from: from));

    if (msg == 'pong' || msg == 'ok' || msg.startsWith('spd:')) {
      _lastPong = DateTime.now();
      if (_status != 'Connected') _setStatus('Connected');
    } else if (msg.startsWith('dist:')) {
      _lastPong = DateTime.now();
      final raw = int.tryParse(msg.substring(5));
      _distanceCm = (raw == null || raw < 0) ? null : raw;
      _lastDistanceAt = DateTime.now();
      if (_status != 'Connected') _setStatus('Connected');
      notifyListeners();
    } else if (msg.startsWith('info:')) {
      _lastPong = DateTime.now();
      final fields = <String, String>{};
      for (final kv in msg.substring(5).split(',')) {
        final i = kv.indexOf('=');
        if (i > 0) fields[kv.substring(0, i)] = kv.substring(i + 1);
      }
      final freq = int.tryParse(fields['freq'] ?? '');
      final res = int.tryParse(fields['res'] ?? '');
      final maxv = int.tryParse(fields['max'] ?? '');
      if (freq != null) _pwmFreqHz = freq;
      if (res != null) _pwmRes = res;
      if (maxv != null) _pwmMax = maxv;
      if (_status != 'Connected') _setStatus('Connected');
      notifyListeners();
    }
  }

  // --- Public API ---
  Future<void> connect(String ip, {bool pushHistory = true}) async {
    final cleaned = ip.trim();
    if (cleaned.isEmpty) {
      _setStatus('Invalid IP');
      return;
    }
    _ip = cleaned;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('esp_ip', cleaned);
    if (pushHistory) await _pushIpHistory(cleaned);
    _setStatus('Searching...');
    notifyListeners();

    try {
      _addr = InternetAddress(cleaned);
      await _initSocket();
      _lastPong = null;
      _send('ping');
      _send('info');
      _send('spd:$_speed');

      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _send('ping');
        final last = _lastPong;
        if (last == null ||
            DateTime.now().difference(last) >
                const Duration(seconds: 5)) {
          if (_status == 'Connected') _setStatus('No response');
        }
      });

      _distanceTimer?.cancel();
      _distanceTimer = Timer.periodic(kDistancePollInterval, (_) {
        _send('dist');
        final last = _lastDistanceAt;
        if (last != null &&
            DateTime.now().difference(last) >
                const Duration(milliseconds: 1500)) {
          if (_distanceCm != null) {
            _distanceCm = null;
            notifyListeners();
          }
        }
      });

      Future.delayed(const Duration(seconds: 2), () {
        if (_lastPong == null) _setStatus('No response');
      });
    } catch (e) {
      _setStatus('Invalid IP');
      _appendLog(LogEntry(LogDirection.error, 'connect failed: $e'));
    }
  }

  void disconnect() {
    _pingTimer?.cancel();
    _distanceTimer?.cancel();
    _repeatTimer?.cancel();
    _socket?.close();
    _socket = null;
    _addr = null;
    _lastPong = null;
    _activeCmd = null;
    _setStatus('Disconnected');
    notifyListeners();
  }

  void _send(String cmd) {
    final sock = _socket;
    final addr = _addr;
    if (sock == null || addr == null) return;
    try {
      sock.send(utf8.encode(cmd), addr, kEspUdpPort);
      _appendLog(LogEntry(LogDirection.tx, cmd, from: addr.address));
    } catch (e) {
      _appendLog(LogEntry(LogDirection.error, 'send failed: $e'));
    }
  }

  void sendRaw(String cmd) => _send(cmd);

  /// Press-and-hold a directional command (maju/mundur/kiri/kanan).
  /// Repeats every [kRepeatInterval] until [pressUp] is called.
  void pressDown(String cmd) {
    _activeCmd = cmd;
    notifyListeners();
    _send(cmd);
    _repeatTimer?.cancel();
    _repeatTimer =
        Timer.periodic(kRepeatInterval, (_) => _send(cmd));
  }

  void pressUp() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _activeCmd = null;
    notifyListeners();
    _send('stop');
    Future.delayed(const Duration(milliseconds: 50), () => _send('stop'));
  }

  Future<void> setSpeed(int value) async {
    final clamped = value.clamp(0, 255);
    _speed = clamped;
    notifyListeners();
    _send('spd:$clamped');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('speed', clamped);
  }

  void setSpeedLocal(int value) {
    _speed = value.clamp(0, 255);
    notifyListeners();
  }

  void requestStop() {
    _repeatTimer?.cancel();
    _send('stop');
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _distanceTimer?.cancel();
    _repeatTimer?.cancel();
    _socket?.close();
    super.dispose();
  }
}
