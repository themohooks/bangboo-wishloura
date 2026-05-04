import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/config_service.dart';
import 'import_config_controller.dart';

const _kSampleJson = '''{
  "name": "My Tunnel",
  "serverHost": "your-server.example.com",
  "serverPort": 443,
  "transportType": "mock",
  "authToken": "your-secret-token",
  "deviceId": "auto",
  "mtu": 1280,
  "dnsServers": ["1.1.1.1", "8.8.8.8"],
  "ipv4Address": "10.7.0.2",
  "ipv4SubnetMask": "255.255.255.0",
  "allowedIPv4Routes": ["0.0.0.0/0"],
  "excludedIPv4Routes": [],
  "keepAliveSeconds": 25,
  "workers": 4,
  "sni": "your-server.example.com",
  "enableUdp": true,
  "enableTcp": true,
  "autoReconnect": true,
  "maxReconnectAttempts": 3
}''';

class ImportConfigScreen extends ConsumerStatefulWidget {
  const ImportConfigScreen({super.key});

  @override
  ConsumerState<ImportConfigScreen> createState() => _ImportConfigScreenState();
}

class _ImportConfigScreenState extends ConsumerState<ImportConfigScreen> {
  final _ctrl = TextEditingController(text: _kSampleJson);
  List<String> _errors = [];
  bool _isValid = false;
  bool _importing = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _validate() {
    final result = ref.read(importConfigControllerProvider).validate(_ctrl.text);
    setState(() {
      _errors = result.errors;
      _isValid = result.isValid;
    });
  }

  Future<void> _import() async {
    _validate();
    if (!_isValid) return;

    setState(() => _importing = true);
    try {
      await ref.read(importConfigControllerProvider).importConfig(_ctrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Configuration imported successfully')),
        );
        setState(() {
          _errors = [];
          _isValid = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Import Config')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Info banner ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Paste your server config JSON below. The authToken will be stored securely and never written to plain storage.',
                      style: TextStyle(fontSize: 12, color: cs.primary.withOpacity(0.8)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // ── JSON textarea ──────────────────────────────────────────
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _errors.isNotEmpty
                        ? cs.error.withOpacity(0.5)
                        : _isValid
                            ? cs.secondary.withOpacity(0.5)
                            : Colors.white12,
                  ),
                ),
                child: TextField(
                  controller: _ctrl,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.all(14),
                    border: InputBorder.none,
                    hintText: 'Paste JSON config here…',
                  ),
                  onChanged: (_) {
                    if (_isValid || _errors.isNotEmpty) {
                      setState(() {
                        _isValid = false;
                        _errors = [];
                      });
                    }
                  },
                ),
              ),
            ),
            // ── Errors ────────────────────────────────────────────────
            if (_errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.error.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _errors.map((e) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline, size: 14, color: cs.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(e, style: TextStyle(fontSize: 12, color: cs.error)),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
            if (_isValid && _errors.isEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.secondary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, size: 14, color: cs.secondary),
                    const SizedBox(width: 6),
                    Text('Config is valid', style: TextStyle(fontSize: 12, color: cs.secondary)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            // ── Actions ───────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _validate,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: cs.primary.withOpacity(0.5)),
                      foregroundColor: cs.primary,
                    ),
                    child: const Text('Validate'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _importing ? null : _import,
                    child: _importing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Text('Import'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
