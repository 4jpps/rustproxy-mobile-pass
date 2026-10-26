// The check-in schedule while the switch is on: check in now, again every [checkEvery], and as soon
// as the phone's network changes, so RustProxy only ever lets in the phone's current IP.

import 'dart:io';

import 'pass_client.dart';

/// Regular check-in interval; RustProxy keeps a pass for 10 minutes, so two chances per pass.
const checkEvery = Duration(minutes: 4);
/// How often the loop looks for a network change.
const tick = Duration(seconds: 30);

class PassStatus {
  final bool ok;
  final String? ip;
  final String? error;
  final DateTime at;

  const PassStatus({required this.ok, this.ip, this.error, required this.at});

  Map<String, Object?> toMap() => {'ok': ok, 'ip': ip, 'error': error, 'at': at.millisecondsSinceEpoch};

  static PassStatus fromMap(Map m) => PassStatus(
        ok: m['ok'] == true,
        ip: m['ip'] as String?,
        error: m['error'] as String?,
        at: DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
      );
}

class PassLoop {
  final void Function(PassStatus) onStatus;
  PassConfig? _cfg;
  DateTime? _lastOk;
  String? _network;

  PassLoop(this.onStatus);

  Future<void> start() async {
    _cfg = await PassConfig.load();
    _network = await networkFingerprint();
    await _checkIn();
  }

  /// Called every [tick].
  Future<void> poll() async {
    final net = await networkFingerprint();
    final changed = net != _network;
    _network = net;
    final due = _lastOk == null || DateTime.now().difference(_lastOk!) >= checkEvery;
    if (changed || due) await _checkIn();
  }

  Future<void> _checkIn() async {
    final cfg = _cfg ?? await PassConfig.load();
    _cfg = cfg;
    if (cfg == null) {
      onStatus(PassStatus(ok: false, error: 'Not set up.', at: DateTime.now()));
      return;
    }
    final r = await checkIn(cfg);
    if (r.ok) _lastOk = DateTime.now();
    onStatus(PassStatus(ok: r.ok, ip: r.ip, error: r.error, at: DateTime.now()));
  }
}

/// The phone's own addresses on every interface. Moving between Wi-Fi and cellular, or to another
/// Wi-Fi, changes this, which triggers an immediate check-in.
Future<String> networkFingerprint() async {
  try {
    final ifaces = await NetworkInterface.list(includeLoopback: false, includeLinkLocal: false);
    final addrs = [for (final i in ifaces) for (final a in i.addresses) '${i.name}=${a.address}']..sort();
    return addrs.join(',');
  } catch (_) {
    return '';
  }
}
