import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/transport_type.dart';
import '../../core/models/tunnel_config.dart';
import '../../core/services/providers.dart';
import '../../core/utils/validators.dart';
import 'settings_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;
  TunnelConfig? _config;

  // Controllers
  late final _nameCtrl = TextEditingController();
  late final _hostCtrl = TextEditingController();
  late final _portCtrl = TextEditingController();
  late final _tokenCtrl = TextEditingController();
  late final _deviceIdCtrl = TextEditingController();
  late final _mtuCtrl = TextEditingController();
  late final _dnsCtrl = TextEditingController(); // comma-separated
  late final _ipv4Ctrl = TextEditingController();
  late final _maskCtrl = TextEditingController();
  late final _allowedCtrl = TextEditingController(); // comma-separated
  late final _excludedCtrl = TextEditingController();
  late final _keepAliveCtrl = TextEditingController();
  late final _workersCtrl = TextEditingController();
  late final _sniCtrl = TextEditingController();
  late final _maxReconnectCtrl = TextEditingController();

  TransportType _transport = TransportType.mock;
  bool _enableUdp = true;
  bool _enableTcp = true;
  bool _autoReconnect = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ctrl = ref.read(settingsControllerProvider);
    final cfg = await ctrl.loadFirst();
    if (cfg != null) {
      final withSecret = await ctrl.loadWithSecret(cfg.id);
      _populate(withSecret ?? cfg);
    } else {
      _populate(ctrl.blank());
    }
    setState(() => _loading = false);
  }

  void _populate(TunnelConfig c) {
    _config = c;
    _nameCtrl.text = c.name;
    _hostCtrl.text = c.serverHost;
    _portCtrl.text = '${c.serverPort}';
    _tokenCtrl.text = c.authToken ?? '';
    _deviceIdCtrl.text = c.deviceId;
    _mtuCtrl.text = '${c.mtu}';
    _dnsCtrl.text = c.dnsServers.join(', ');
    _ipv4Ctrl.text = c.ipv4Address;
    _maskCtrl.text = c.ipv4SubnetMask;
    _allowedCtrl.text = c.allowedIPv4Routes.join(', ');
    _excludedCtrl.text = c.excludedIPv4Routes.join(', ');
    _keepAliveCtrl.text = '${c.keepAliveSeconds}';
    _workersCtrl.text = '${c.workers}';
    _sniCtrl.text = c.sni ?? '';
    _maxReconnectCtrl.text = '${c.maxReconnectAttempts}';
    _transport = c.transportType;
    _enableUdp = c.enableUdp;
    _enableTcp = c.enableTcp;
    _autoReconnect = c.autoReconnect;
  }

  TunnelConfig _collect() {
    final base = _config ?? TunnelConfig.defaults;
    return base.copyWith(
      name: _nameCtrl.text.trim(),
      serverHost: _hostCtrl.text.trim(),
      serverPort: int.tryParse(_portCtrl.text.trim()) ?? 443,
      transportType: _transport,
      authToken: _tokenCtrl.text.trim().isEmpty ? null : _tokenCtrl.text.trim(),
      deviceId: _deviceIdCtrl.text.trim(),
      mtu: int.tryParse(_mtuCtrl.text.trim()) ?? 1280,
      dnsServers: _splitList(_dnsCtrl.text),
      ipv4Address: _ipv4Ctrl.text.trim(),
      ipv4SubnetMask: _maskCtrl.text.trim(),
      allowedIPv4Routes: _splitList(_allowedCtrl.text),
      excludedIPv4Routes: _splitList(_excludedCtrl.text),
      keepAliveSeconds: int.tryParse(_keepAliveCtrl.text.trim()) ?? 25,
      workers: int.tryParse(_workersCtrl.text.trim()) ?? 4,
      sni: _sniCtrl.text.trim().isEmpty ? null : _sniCtrl.text.trim(),
      enableUdp: _enableUdp,
      enableTcp: _enableTcp,
      autoReconnect: _autoReconnect,
      maxReconnectAttempts: int.tryParse(_maxReconnectCtrl.text.trim()) ?? 3,
      updatedAt: DateTime.now(),
    );
  }

  static List<String> _splitList(String raw) =>
      raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final config = _collect();
      final saved = await ref.read(configServiceProvider).save(config);
      setState(() => _config = saved.copyWith(clearAuthToken: false));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuration saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _hostCtrl, _portCtrl, _tokenCtrl, _deviceIdCtrl,
      _mtuCtrl, _dnsCtrl, _ipv4Ctrl, _maskCtrl, _allowedCtrl,
      _excludedCtrl, _keepAliveCtrl, _workersCtrl, _sniCtrl, _maxReconnectCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(icon: const Icon(Icons.save_outlined), onPressed: _save, tooltip: 'Save'),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            _Section('Profile'),
            _Field('Profile Name', _nameCtrl),
            _Section('Server'),
            _Field(
              'Server Host',
              _hostCtrl,
              hint: 'example.com',
              validator: Validators.serverHost,
            ),
            _Field(
              'Server Port',
              _portCtrl,
              hint: '443',
              keyboard: TextInputType.number,
              validator: Validators.serverPort,
            ),
            _Section('Transport'),
            _TransportPicker(
              value: _transport,
              onChanged: (t) => setState(() => _transport = t),
            ),
            _Section('Authentication'),
            _Field(
              'Auth Token / Password',
              _tokenCtrl,
              hint: 'Leave empty for no auth',
              obscure: true,
            ),
            _Field('Device ID', _deviceIdCtrl, hint: 'auto'),
            _Section('Network'),
            _Field(
              'IPv4 Address',
              _ipv4Ctrl,
              hint: '10.7.0.2',
              validator: Validators.ipAddress,
            ),
            _Field('Subnet Mask', _maskCtrl, hint: '255.255.255.0'),
            _Field('DNS Servers', _dnsCtrl, hint: '1.1.1.1, 8.8.8.8'),
            _Field(
              'MTU',
              _mtuCtrl,
              hint: '1280',
              keyboard: TextInputType.number,
              validator: Validators.mtu,
            ),
            _Section('Routes'),
            _Field('Allowed IPv4 Routes', _allowedCtrl, hint: '0.0.0.0/0'),
            _Field('Excluded IPv4 Routes', _excludedCtrl, hint: '192.168.0.0/16'),
            _Section('Advanced'),
            _Field('SNI', _sniCtrl, hint: 'example.com (optional)'),
            _Field(
              'Keep-alive (seconds)',
              _keepAliveCtrl,
              hint: '25',
              keyboard: TextInputType.number,
              validator: Validators.keepAlive,
            ),
            _Field(
              'Workers',
              _workersCtrl,
              hint: '4',
              keyboard: TextInputType.number,
              validator: Validators.workers,
            ),
            _Field(
              'Max Reconnect Attempts',
              _maxReconnectCtrl,
              hint: '3',
              keyboard: TextInputType.number,
            ),
            _Section('Flags'),
            _Toggle('Enable UDP', _enableUdp, (v) => setState(() => _enableUdp = v)),
            _Toggle('Enable TCP', _enableTcp, (v) => setState(() => _enableTcp = v)),
            _Toggle('Auto Reconnect', _autoReconnect, (v) => setState(() => _autoReconnect = v)),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF00C8FF),
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(
    this.label,
    this.controller, {
    this.hint,
    this.obscure = false,
    this.keyboard = TextInputType.text,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final TextInputType keyboard;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboard,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
        ),
        validator: validator,
      ),
    );
  }
}

class _TransportPicker extends StatelessWidget {
  const _TransportPicker({required this.value, required this.onChanged});

  final TransportType value;
  final ValueChanged<TransportType> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<TransportType>(
        value: value,
        dropdownColor: const Color(0xFF242424),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: const InputDecoration(labelText: 'Transport Type'),
        items: TransportType.values
            .map((t) => DropdownMenuItem(value: t, child: Text(t.displayName)))
            .toList(),
        onChanged: (t) => t != null ? onChanged(t) : null,
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.label, this.value, this.onChanged);

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}
