import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/tunnel_status.dart';
import '../../core/services/providers.dart';
import '../../core/utils/byte_formatter.dart';
import 'dashboard_controller.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(tunnelStatusProvider);
    final stats = ref.watch(trafficStatsProvider);
    final activeConfig = ref.watch(activeConfigProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('VPN Go')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            const SizedBox(height: 24),
            // ── Big connect button ──────────────────────────────────────
            _ConnectButton(status: status),
            const SizedBox(height: 32),
            // ── Status card ─────────────────────────────────────────────
            _StatusCard(status: status, activeConfig: activeConfig),
            const SizedBox(height: 8),
            // ── Traffic stats ────────────────────────────────────────────
            if (status.status.isActive) ...[
              _TrafficCard(stats: stats),
              const SizedBox(height: 8),
            ],
            // ── Error banner ─────────────────────────────────────────────
            if (status.lastError != null && status.lastError!.isNotEmpty)
              _ErrorBanner(error: status.lastError!),
          ],
        ),
      ),
    );
  }
}

// ── Connect button ────────────────────────────────────────────────────────

class _ConnectButton extends ConsumerWidget {
  const _ConnectButton({required this.status});

  final TunnelStatusState status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final controller = ref.read(dashboardControllerProvider);

    Color ringColor;
    Color bgColor;
    String label;
    bool isLoading;

    switch (status.status) {
      case TunnelStatus.connected:
        ringColor = cs.secondary; // green
        bgColor = cs.secondary.withOpacity(0.15);
        label = 'Disconnect';
        isLoading = false;
      case TunnelStatus.connecting:
      case TunnelStatus.preparing:
        ringColor = cs.primary; // cyan
        bgColor = cs.primary.withOpacity(0.1);
        label = 'Connecting…';
        isLoading = true;
      case TunnelStatus.disconnecting:
        ringColor = Colors.orange;
        bgColor = Colors.orange.withOpacity(0.1);
        label = 'Disconnecting…';
        isLoading = true;
      case TunnelStatus.reconnecting:
        ringColor = Colors.amber;
        bgColor = Colors.amber.withOpacity(0.1);
        label = 'Reconnecting…';
        isLoading = true;
      case TunnelStatus.failed:
        ringColor = cs.error;
        bgColor = cs.error.withOpacity(0.1);
        label = 'Retry';
        isLoading = false;
      default:
        ringColor = Colors.white24;
        bgColor = Colors.white.withOpacity(0.05);
        label = 'Connect';
        isLoading = false;
    }

    return GestureDetector(
      onTap: status.isTransitioning
          ? null
          : () async {
              try {
                await controller.toggleConnection();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              }
            },
      child: Column(
        children: [
          _PulsingRing(
            color: ringColor,
            isAnimating: isLoading,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bgColor,
                border: Border.all(color: ringColor, width: 2.5),
              ),
              child: isLoading
                  ? Center(
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: ringColor,
                        ),
                      ),
                    )
                  : Center(
                      child: Icon(
                        status.status == TunnelStatus.connected
                            ? Icons.shield
                            : Icons.shield_outlined,
                        size: 56,
                        color: ringColor,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: ringColor,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingRing extends StatefulWidget {
  const _PulsingRing({
    required this.color,
    required this.isAnimating,
    required this.child,
  });

  final Color color;
  final bool isAnimating;
  final Widget child;

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale = Tween(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isAnimating) return widget.child;
    return AnimatedBuilder(
      animation: _scale,
      builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
      child: widget.child,
    );
  }
}

// ── Status card ───────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.activeConfig});

  final TunnelStatusState status;
  final dynamic activeConfig;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color statusColor;
    switch (status.status) {
      case TunnelStatus.connected:
        statusColor = cs.secondary;
      case TunnelStatus.failed:
        statusColor = cs.error;
      case TunnelStatus.connecting:
      case TunnelStatus.preparing:
      case TunnelStatus.reconnecting:
        statusColor = cs.primary;
      default:
        statusColor = Colors.white38;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                    boxShadow: status.status.isActive
                        ? [BoxShadow(color: statusColor.withOpacity(0.6), blurRadius: 8, spreadRadius: 2)]
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  status.status.displayName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ],
            ),
            if (status.serverHost != null) ...[
              const SizedBox(height: 12),
              _InfoRow(label: 'Server', value: status.serverHost!),
            ],
            if (status.transportType != null) ...[
              const SizedBox(height: 6),
              _InfoRow(label: 'Transport', value: status.transportType!),
            ],
            if (status.uptimeSeconds != null) ...[
              const SizedBox(height: 6),
              _InfoRow(label: 'Uptime', value: ByteFormatter.formatUptime(status.uptimeSeconds!)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Traffic card ──────────────────────────────────────────────────────────

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({required this.stats});

  final dynamic stats;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    icon: Icons.arrow_downward_rounded,
                    color: const Color(0xFF00E676),
                    label: 'Download',
                    value: ByteFormatter.format(stats.bytesIn),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatTile(
                    icon: Icons.arrow_upward_rounded,
                    color: const Color(0xFF00C8FF),
                    label: 'Upload',
                    value: ByteFormatter.format(stats.bytesOut),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    icon: Icons.inbox_rounded,
                    color: Colors.white54,
                    label: 'Packets In',
                    value: '${stats.packetsIn}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatTile(
                    icon: Icons.outbox_rounded,
                    color: Colors.white54,
                    label: 'Packets Out',
                    value: '${stats.packetsOut}',
                  ),
                ),
              ],
            ),
            if (stats.activeStreams > 0) ...[
              const SizedBox(height: 12),
              _InfoRow(label: 'Active Streams', value: '${stats.activeStreams}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, color: color.withOpacity(0.8))),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.error.withOpacity(0.12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: cs.error, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                error,
                style: TextStyle(color: cs.error, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label: ', style: const TextStyle(color: Colors.white38, fontSize: 13)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
