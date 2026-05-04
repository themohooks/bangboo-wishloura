import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/diagnostics_service.dart';
import '../../core/services/providers.dart';

class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  DiagnosticsReport? _report;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _collect();
  }

  Future<void> _collect() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await ref.read(diagnosticsServiceProvider).collect();
      setState(() => _report = report);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _export() async {
    if (_report == null) return;
    await Clipboard.setData(ClipboardData(text: _report!.toJsonString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diagnostics JSON copied to clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: _collect,
            tooltip: 'Refresh',
          ),
          if (_report != null)
            IconButton(
              icon: const Icon(Icons.copy_outlined),
              onPressed: _export,
              tooltip: 'Export JSON',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Failed to collect diagnostics:\n$_error',
                      style: TextStyle(color: cs.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _report == null
                  ? const SizedBox()
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        _DiagSection('Application'),
                        _DiagRow('Platform', _report!.platform),
                        _DiagRow('App Version', '${_report!.appVersion} (${_report!.buildNumber})'),
                        _DiagRow('OS Version', _report!.osVersion),
                        _DiagRow('Device', _report!.deviceModel),
                        _DiagSection('Go Client'),
                        _DiagRow('Go Client Version', _report!.goClientVersion),
                        _DiagSection('VPN'),
                        _DiagRow(
                          'VPN Permission',
                          _report!.vpnPermissionGranted ? '✓ Granted' : '✗ Not granted',
                          valueColor: _report!.vpnPermissionGranted
                              ? cs.secondary
                              : cs.error,
                        ),
                        _DiagRow('NE Status', _report!.networkExtensionStatus),
                        _DiagSection('Identifiers'),
                        _DiagRow('Runner Bundle ID', _report!.runnerBundleId),
                        _DiagRow('Extension Bundle ID', _report!.extensionBundleId),
                        _DiagRow('App Group ID', _report!.appGroupId),
                        _DiagRow('Keychain Access Group', _report!.keychainAccessGroup),
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.copy_outlined, size: 16),
                            label: const Text('Copy Diagnostics JSON'),
                            onPressed: _export,
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
    );
  }
}

class _DiagSection extends StatelessWidget {
  const _DiagSection(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
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

class _DiagRow extends StatelessWidget {
  const _DiagRow(this.label, this.value, {this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.white70,
                fontSize: 13,
                fontFamily: value.contains('.') || value.contains('/') ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
