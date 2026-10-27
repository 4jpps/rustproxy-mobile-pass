// The check-in schedule while the switch is on: check in now, again well before the pass RustProxy
// granted runs out, and as soon as the phone's network changes, so RustProxy only ever lets in the
// phone's current IP. Frequent check-ins also catch a public IP that changes underneath the phone
// (carrier NAT, a router's new WAN address) without any local network change.

import 'dart:io';

import 'pass_client.dart';

/// How often the loop looks for a network change and whether a check-in is due.
const tick = Duration(seconds: 10);
/// Check-ins happen three times per pass (RustProxy says how long each pass lasts), but never more
/// often than every 20 s and never less often than every 4 minutes.
const minCheckEvery = Duration(seconds: 20);
const maxCheckEvery = Duration(minutes: 4);

/// The check-in interval for a pass that lasts [expiresIn] seconds.
Duration checkEveryFor(int expiresIn) {
  if (expiresIn <= 0) return maxCheckEvery;
  final third = Duration(seconds: expiresIn ~/ 3);
  if (third < minCheckEvery) return minCheckEvery;
  if (third > maxCheckEvery) return maxCheckEvery;
  return third;
}

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
  Duration _checkEvery = maxCheckEvery;
  /// Seconds the last granted pass lasts, for "ends within" messages.
  int lastExpiresIn = 0;
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
    final due = _lastOk == null || DateTime.now().difference(_lastOk!) >= _checkEvery;
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
    if (r.ok) {
      _lastOk = DateTime.now();
      _checkEvery = checkEveryFor(r.expiresIn);
      lastExpiresIn = r.expiresIn;
    } else {
      // A failed check-in (no network, server busy) is retried at the next tick, not after a full
      // interval, so the pass isn't left to run out.
      _lastOk = null;
    }
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
