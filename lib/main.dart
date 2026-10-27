// RustProxy Mobile Pass: while switched on, keeps this phone's *current* IP inside the RustProxy IP
// allow lists that accept its login, so sites locked to home or the office work from cellular.

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'pass_client.dart';
import 'pass_loop.dart';
import 'pass_service.dart';

const _bg = Color(0xFF0F1215);
const _card = Color(0xFF181C21);
const _accent = Color(0xFFE2703A);
const _ink = Color(0xFFF4EFE9);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PassService.init();
  runApp(const MobilePassApp());
}

class MobilePassApp extends StatelessWidget {
  const MobilePassApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: _accent, brightness: Brightness.dark, surface: _bg, primary: _accent);
    return MaterialApp(
      title: 'RustProxy Mobile Pass',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, scaffoldBackgroundColor: _bg, useMaterial3: true),
      home: const WithForegroundTask(child: HomePage()),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final PassService _service = PassService(_onStatus);
  PassConfig? _cfg;
  bool _loaded = false, _on = false, _busy = false;
  PassStatus? _status;

  @override
  void initState() {
    super.initState();
    _service.attach();
    _load();
  }

  @override
  void dispose() {
    _service.detach();
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await PassConfig.load();
    var on = await _service.running;
    // Left on last time but not running now (app reopened on desktop/iOS): resume.
    if (!on && cfg != null && await PassConfig.loadEnabled()) {
      on = (await _service.start()) == null;
    }
    setState(() {
      _cfg = cfg;
      _on = on;
      _loaded = true;
    });
  }

  void _onStatus(PassStatus s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _toggle(bool want) async {
    setState(() => _busy = true);
    if (want) {
      final err = await _service.start();
      await PassConfig.saveEnabled(err == null);
      setState(() {
        _on = err == null;
        if (err != null) _status = PassStatus(ok: false, error: err, at: DateTime.now());
      });
    } else {
      await PassConfig.saveEnabled(false);
      final r = await _service.stop();
      setState(() {
        _on = false;
        _status = PassStatus(
          ok: false,
          error: r == null || r.ok ? 'Off. This phone\'s pass has ended.' : 'Off here, but RustProxy could not be told (${r.error}); the pass ends by itself within about a minute and a half.',
          at: DateTime.now(),
        );
      });
    }
    setState(() => _busy = false);
  }

  Future<void> _openSetup() async {
    if (_on) await _toggle(false);
    if (!mounted) return;
    final saved = await Navigator.of(context).push<PassConfig>(MaterialPageRoute(builder: (_) => SetupPage(initial: _cfg)));
    if (saved != null) setState(() => _cfg = saved);
  }

  Future<void> _forget() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Forget this phone?'),
        content: const Text('Turns the pass off and removes the saved server, username and password from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Forget')),
        ],
      ),
    );
    if (yes != true) return;
    if (_on) await _toggle(false);
    await PassConfig.forget();
    setState(() {
      _cfg = null;
      _status = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final cfg = _cfg;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Text('Mobile Pass'),
        actions: [
          if (cfg != null) IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings), onPressed: _openSetup),
          if (cfg != null) IconButton(tooltip: 'Forget this phone', icon: const Icon(Icons.logout), onPressed: _forget),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: cfg == null ? [_welcome()] : [_switchCard(cfg), const SizedBox(height: 16), _statusCard(), const SizedBox(height: 16), _about()],
        ),
      ),
    );
  }

  Widget _welcome() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset('assets/icon.png', width: 96, height: 96),
          const SizedBox(height: 16),
          const Text('Reach your own sites from anywhere', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: _ink)),
          const SizedBox(height: 8),
          const Text(
            'Sign in with a login from your RustProxy. While the switch is on, RustProxy lets this phone\'s current network '
            'through the IP allow lists that accept that login, and stops the moment you switch it off or change networks.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: _openSetup, icon: const Icon(Icons.login), label: const Text('Sign in')),
        ],
      );

  Widget _switchCard(PassConfig cfg) => Card(
        color: _card,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_on ? 'Pass on' : 'Pass off', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: _on ? _accent : _ink)),
                    const SizedBox(height: 4),
                    Text('${cfg.username} · ${cfg.device}', style: const TextStyle(color: Colors.white70)),
                    Text(cfg.endpoint.host, style: const TextStyle(color: Colors.white54)),
                  ],
                ),
              ),
              Transform.scale(
                scale: 1.4,
                child: Switch(value: _on, onChanged: _busy ? null : _toggle),
              ),
            ],
          ),
        ),
      );

  Widget _statusCard() {
    final s = _status;
    String line;
    IconData icon;
    Color color;
    if (s == null) {
      line = _on ? 'Checking in…' : 'Switch on to let this phone through.';
      icon = _on ? Icons.sync : Icons.pause_circle_outline;
      color = Colors.white54;
    } else if (s.ok) {
      line = 'Let in as ${s.ip ?? 'this phone'}\nLast check-in ${TimeOfDay.fromDateTime(s.at).format(context)}';
      icon = Icons.verified_user;
      color = _accent;
    } else {
      line = s.error ?? 'Not active';
      icon = _on ? Icons.warning_amber : Icons.pause_circle_outline;
      color = _on ? Colors.amber : Colors.white54;
    }
    return Card(
      color: _card,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: Icon(icon, color: color, size: 32),
        title: Text(line, style: const TextStyle(color: _ink, height: 1.4)),
      ),
    );
  }

  Widget _about() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'Only this phone\'s current IP is let in. It checks in about every half minute and right after the network changes; '
          'the previous network is dropped at once. Turning the switch off ends the pass at once, and a phone that stops '
          'checking in (offline, app closed) drops out within about a minute and a half. '
          'No history of addresses is kept on the phone or on RustProxy.',
          style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
        ),
      );
}

class SetupPage extends StatefulWidget {
  final PassConfig? initial;
  const SetupPage({super.key, this.initial});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _form = GlobalKey<FormState>();
  late final _server = TextEditingController(text: widget.initial?.server ?? '');
  late final _user = TextEditingController(text: widget.initial?.username ?? '');
  late final _pass = TextEditingController(text: widget.initial?.password ?? '');
  late final _device = TextEditingController(text: widget.initial?.device ?? 'My phone');
  bool _busy = false, _hide = true;
  String? _error;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final cfg = PassConfig(server: _server.text.trim(), username: _user.text.trim(), password: _pass.text, device: _device.text.trim());
    setState(() {
      _busy = true;
      _error = null;
    });
    // Prove the login works now (this also grants the first pass), then end it: the switch starts off.
    final r = await checkIn(cfg);
    if (r.ok) await signOut(cfg);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = r.error;
      });
      return;
    }
    await cfg.save();
    if (mounted) Navigator.of(context).pop(cfg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: _bg, title: const Text('Sign in')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _server,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'RustProxy site', hintText: 'hermes.example.com', helperText: 'Any https site this RustProxy serves'),
                validator: (v) {
                  try {
                    passUri(v ?? '');
                    return null;
                  } on FormatException catch (e) {
                    return e.message;
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _user,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Username', helperText: 'A login from the list your RustProxy accepts for mobile passes'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pass,
                obscureText: _hide,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _hide = !_hide)),
                ),
                validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _device,
                decoration: const InputDecoration(labelText: 'Name for this phone', helperText: 'Shown on RustProxy\'s Mobile passes page'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.amber)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Check and save'),
              ),
              const SizedBox(height: 12),
              const Text('The password is kept in this device\'s secure storage and is only ever sent over HTTPS to your RustProxy.',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
