// Talks to RustProxy's mobile-pass endpoint: POST signs the phone in (its current IP gets the pass),
// DELETE signs it out (the pass ends at once).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Where RustProxy answers check-ins, on any site it serves.
const passPath = '/.rust-proxy/mobile-pass';

/// What the app remembers, kept in the phone's secure storage (Keystore / Keychain).
class PassConfig {
  final String server;
  final String username;
  final String password;
  final String device;

  const PassConfig({required this.server, required this.username, required this.password, required this.device});

  static const _storage = FlutterSecureStorage();

  static Future<PassConfig?> load() async {
    final v = await _storage.readAll();
    final server = v['server'], username = v['username'], password = v['password'];
    if (server == null || username == null || password == null) return null;
    return PassConfig(server: server, username: username, password: password, device: v['device'] ?? 'phone');
  }

  Future<void> save() async {
    await _storage.write(key: 'server', value: server);
    await _storage.write(key: 'username', value: username);
    await _storage.write(key: 'password', value: password);
    await _storage.write(key: 'device', value: device);
  }

  static Future<void> forget() => _storage.deleteAll();

  /// Whether the switch was left on (so the pass resumes after a restart of the app or phone).
  static Future<bool> loadEnabled() async => (await _storage.read(key: 'enabled')) == 'true';
  static Future<void> saveEnabled(bool on) => _storage.write(key: 'enabled', value: on ? 'true' : 'false');

  /// `hermes.example.com`, `https://hermes.example.com/anything` -> `https://hermes.example.com/.rust-proxy/mobile-pass`.
  /// Only HTTPS: the password must never cross the network in the clear.
  Uri get endpoint => passUri(server);
}

Uri passUri(String server) {
  var s = server.trim();
  if (!s.contains('://')) s = 'https://$s';
  final u = Uri.parse(s);
  if (u.scheme != 'https' || u.host.isEmpty) {
    throw const FormatException('Use the https:// address of a site on your RustProxy.');
  }
  return Uri(scheme: 'https', host: u.host, port: u.hasPort ? u.port : null, path: passPath);
}

/// The answer to one check-in.
class CheckIn {
  final bool ok;
  /// The IP RustProxy saw (shown on screen only, never stored).
  final String? ip;
  final int expiresIn;
  final String? error;
  /// True when trying again later can help (no network, server busy).
  final bool retry;

  const CheckIn({required this.ok, this.ip, this.expiresIn = 0, this.error, this.retry = false});
}

Future<CheckIn> checkIn(PassConfig cfg) => _send('POST', cfg);

Future<CheckIn> signOut(PassConfig cfg) => _send('DELETE', cfg);

Future<CheckIn> _send(String method, PassConfig cfg) async {
  try {
    final req = http.Request(method, cfg.endpoint)
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'username': cfg.username, 'password': cfg.password, 'device': cfg.device});
    final resp = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 20)));
    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {}
    switch (resp.statusCode) {
      case 200:
        return CheckIn(ok: true, ip: body['ip'] as String?, expiresIn: (body['expires_in'] as num?)?.toInt() ?? 0);
      case 401:
        return const CheckIn(ok: false, error: 'Wrong username or password.');
      case 404:
        return const CheckIn(ok: false, error: 'Mobile passes are turned off on this RustProxy (or this is not a RustProxy site).');
      case 429:
        return const CheckIn(ok: false, error: 'Too many wrong passwords from this network. Try again in 15 minutes.', retry: true);
      default:
        return CheckIn(ok: false, error: 'RustProxy answered ${resp.statusCode}.', retry: true);
    }
  } on FormatException catch (e) {
    return CheckIn(ok: false, error: e.message);
  } on SocketException {
    return const CheckIn(ok: false, error: 'No connection to RustProxy.', retry: true);
  } on HandshakeException {
    return const CheckIn(ok: false, error: "Couldn't verify the site's certificate.", retry: true);
  } catch (e) {
    return CheckIn(ok: false, error: 'Check-in failed: $e', retry: true);
  }
}
