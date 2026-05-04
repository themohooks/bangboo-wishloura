import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_info.dart';
import '../../core/services/providers.dart';

/// App exclusions screen — mirrors ExceptionsTab from proxy-turn-vk-android.
///
/// Modes:
///   Blacklist (ЧС): listed apps BYPASS the VPN tunnel.
///   Whitelist (БС): ONLY listed apps go THROUGH the VPN tunnel.
///
/// Changes are applied live via setExcludedApps() while the tunnel is running.
class AppExclusionsScreen extends ConsumerStatefulWidget {
  const AppExclusionsScreen({super.key});

  @override
  ConsumerState<AppExclusionsScreen> createState() => _AppExclusionsScreenState();
}

class _AppExclusionsScreenState extends ConsumerState<AppExclusionsScreen> {
  final _searchCtrl = TextEditingController();

  // Local mutable copy of exclusion states
  final Map<String, bool> _excluded = {};
  bool _isWhitelist = false;
  bool _isDirty = false;
  bool _saving = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onAppToggled(AppInfo app, bool value) {
    setState(() {
      _excluded[app.packageName] = value;
      _isDirty = true;
    });
  }

  void _toggleMode() {
    setState(() {
      _isWhitelist = !_isWhitelist;
      _isDirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final packages = _excluded.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();
      await ref
          .read(vpnPlatformServiceProvider)
          .setExcludedApps(packages, isWhitelist: _isWhitelist);
      ref.invalidate(installedAppsProvider);
      setState(() => _isDirty = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exclusions saved & tunnel reloaded')),
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
  Widget build(BuildContext context) {
    final appsAsync = ref.watch(installedAppsProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Exclusions'),
        actions: [
          if (_isDirty)
            _saving
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    icon: const Icon(Icons.save_outlined),
                    onPressed: _save,
                    tooltip: 'Save & apply',
                  ),
        ],
      ),
      body: appsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.android, color: cs.error, size: 48),
                const SizedBox(height: 12),
                Text(
                  'App list unavailable\n(Android only)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.error),
                ),
              ],
            ),
          ),
        ),
        data: (apps) {
          // Seed local state on first load
          if (_excluded.isEmpty && apps.isNotEmpty) {
            for (final app in apps) {
              _excluded[app.packageName] = app.isExcluded;
            }
            _isWhitelist = apps.first.isWhitelist;
          }

          return Column(
            children: [
              // ── Mode selector ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: _ModeChip(
                        label: 'Blacklist',
                        subtitle: 'Checked apps bypass tunnel',
                        selected: !_isWhitelist,
                        onTap: () => setState(() { _isWhitelist = false; _isDirty = true; }),
                        cs: cs,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ModeChip(
                        label: 'Whitelist',
                        subtitle: 'Checked apps use tunnel',
                        selected: _isWhitelist,
                        onTap: () => setState(() { _isWhitelist = true; _isDirty = true; }),
                        cs: cs,
                      ),
                    ),
                  ],
                ),
              ),
              // ── Search ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search apps…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              ref.read(appSearchQueryProvider.notifier).state = '';
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) {
                    ref.read(appSearchQueryProvider.notifier).state = v;
                  },
                ),
              ),
              // ── App list ────────────────────────────────────────────────
              Expanded(
                child: _buildAppList(apps, cs),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAppList(List<AppInfo> apps, ColorScheme cs) {
    final query = ref.watch(appSearchQueryProvider).toLowerCase();
    final filtered = query.isEmpty
        ? apps
        : apps.where((a) =>
            a.label.toLowerCase().contains(query) ||
            a.packageName.toLowerCase().contains(query)).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text('No apps found', style: TextStyle(color: cs.onSurface.withOpacity(0.4))),
      );
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final app = filtered[i];
        final isChecked = _excluded[app.packageName] ?? false;
        return _AppRow(
          app: app,
          isChecked: isChecked,
          isWhitelist: _isWhitelist,
          onChanged: (v) => _onAppToggled(app, v),
          cs: cs,
        );
      },
    );
  }
}

// ── Mode chip ────────────────────────────────────────────────────────────────

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    required this.cs,
  });
  final String label, subtitle;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withOpacity(0.12) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : Colors.white12,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 16,
                  color: selected ? cs.primary : Colors.white38,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? cs.primary : Colors.white54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.white38)),
          ],
        ),
      ),
    );
  }
}

// ── App row ──────────────────────────────────────────────────────────────────

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.isChecked,
    required this.isWhitelist,
    required this.onChanged,
    required this.cs,
  });
  final AppInfo app;
  final bool isChecked, isWhitelist;
  final ValueChanged<bool> onChanged;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: _AppIcon(iconBase64: app.iconBase64),
      title: Text(
        app.label,
        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        app.packageName,
        style: const TextStyle(color: Colors.white38, fontSize: 11),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Checkbox(
        value: isChecked,
        onChanged: (v) => onChanged(v ?? false),
        activeColor: isWhitelist ? cs.secondary : cs.primary,
        checkColor: Colors.black,
        side: BorderSide(color: Colors.white24),
      ),
      onTap: () => onChanged(!isChecked),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.iconBase64});
  final String iconBase64;

  @override
  Widget build(BuildContext context) {
    try {
      final bytes = base64Decode(iconBase64);
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(bytes, width: 36, height: 36, fit: BoxFit.cover),
      );
    } catch (_) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.android, size: 20, color: Colors.white38),
      );
    }
  }
}
