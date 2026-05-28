// lib/screens/dashboard_screen.dart
// Main overview screen — CP identity, connection state, connector status cards.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cp_provider.dart';
import '../models/cp_models.dart';
import '../utils/app_theme.dart';
import '../widgets/shared_widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CpProvider>(
      builder: (context, provider, _) {
        return RefreshIndicator(
          color: AppTheme.primary,
          backgroundColor: AppTheme.surfaceCard,
          onRefresh: () async {},
          child: CustomScrollView(
            slivers: [
              // ── Identity Card ─────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _IdentityCard(provider: provider),
                ),
              ),

              // ── Stats row ─────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _StatsRow(provider: provider),
                ),
              ),

              // ── Connectors ────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
                  child: SectionHeader(
                    title: 'CONNECTORS',
                    trailing: StatusPill(
                      label: '${provider.connectors.length} total',
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),

              if (provider.connectors.isEmpty)
                const SliverFillRemaining(
                  child: EmptyState(
                    icon: Icons.power_outlined,
                    title: 'No connectors configured',
                    subtitle: 'Go to Settings to set connector count',
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: _ConnectorCard(
                        connectorState: provider.connectors[i],
                        provider: provider,
                      ),
                    ),
                    childCount: provider.connectors.length,
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    );
  }
}

// ─── Identity Card ────────────────────────────────────────────────────────────

class _IdentityCard extends StatelessWidget {
  final CpProvider provider;
  const _IdentityCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final s = provider.settings;
    return CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.ev_station, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.chargePointId,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      '${s.vendor} ${s.model}',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _ConnectionBadge(state: provider.connectionState),
                  if (provider.isBooted) ...[
                    const SizedBox(height: 4),
                    StatusPill(label: 'BOOTED', color: AppTheme.primary, fontSize: 10),
                  ],
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),

          Row(
            children: [
              _MiniInfo('Serial', s.serialNumber),
              _MiniInfo('FW', s.firmwareVersion),
              _MiniInfo('Connectors', '${s.connectorCount}'),
              _MiniInfo('Heartbeat', '${s.heartbeatIntervalSec}s'),
            ],
          ),

          const SizedBox(height: 14),

          // Boot / Connect / Disconnect button
          _ActionRow(provider: provider),
        ],
      ),
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  final CpConnectionState state;
  const _ConnectionBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (state) {
      case CpConnectionState.connected:
        color = AppTheme.available; label = 'CONNECTED';
        break;
      case CpConnectionState.connecting:
        color = AppTheme.warning; label = 'CONNECTING';
        break;
      case CpConnectionState.reconnecting:
        color = AppTheme.warning; label = 'RECONNECTING';
        break;
      case CpConnectionState.disconnected:
        color = AppTheme.error; label = 'OFFLINE';
        break;
    }
    return StatusPill(label: label, color: color, fontSize: 10);
  }
}

class _MiniInfo extends StatelessWidget {
  final String label;
  final String value;
  const _MiniInfo(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
          Text(label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final CpProvider provider;
  const _ActionRow({required this.provider});

  @override
  Widget build(BuildContext context) {
    final isConnecting = provider.connectionState == CpConnectionState.connecting;
    final isReconnecting = provider.connectionState == CpConnectionState.reconnecting;

    if (!provider.isConnected) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: isConnecting || isReconnecting ? null : provider.connect,
          icon: isConnecting || isReconnecting
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.surface))
              : const Icon(Icons.wifi, size: 18),
          label: Text(isConnecting ? 'Connecting...' : 'Connect to Backend'),
        ),
      );
    }

    if (!provider.isBooted) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: provider.boot,
              icon: const Icon(Icons.power_settings_new, size: 18),
              label: const Text('Boot Charge Point'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: provider.disconnect,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.error,
              side: const BorderSide(color: AppTheme.error),
            ),
            child: const Text('Disconnect'),
          ),
        ],
      );
    }

    // Connected and booted
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _confirmReboot(context, provider),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Reboot'),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () => _confirmDisconnect(context, provider),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.error,
            side: const BorderSide(color: AppTheme.error),
          ),
          child: const Text('Disconnect'),
        ),
      ],
    );
  }

  Future<void> _confirmReboot(BuildContext context, CpProvider provider) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        title: const Text('Reboot Charge Point?'),
        content: const Text('This will stop all active sessions and send BootNotification again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reboot')),
        ],
      ),
    );
    if (ok == true) {
      await provider.disconnect();
      await Future.delayed(const Duration(milliseconds: 500));
      await provider.connect();
      await Future.delayed(const Duration(milliseconds: 800));
      await provider.boot();
    }
  }

  Future<void> _confirmDisconnect(BuildContext context, CpProvider provider) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        title: const Text('Disconnect?'),
        content: const Text('All active sessions will be stopped and the CP will go offline.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (ok == true) provider.disconnect();
  }
}

// ─── Stats Row ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final CpProvider provider;
  const _StatsRow({required this.provider});

  @override
  Widget build(BuildContext context) {
    final charging   = provider.connectors.where((c) => c.isCharging).length;
    final available  = provider.connectors.where((c) => c.status == ConnectorStatus.Available).length;
    final totalEnergy = provider.connectors.fold(0.0, (sum, c) => sum + c.energyDeliveredKwh);

    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Charging',
            value: '$charging',
            color: AppTheme.charging,
            icon: Icons.bolt,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: 'Available',
            value: '$available',
            color: AppTheme.available,
            icon: Icons.check_circle_outline,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: 'kWh Today',
            value: totalEnergy.toStringAsFixed(1),
            color: AppTheme.info,
            icon: Icons.energy_savings_leaf_outlined,
          ),
        ),
      ],
    );
  }
}

// ─── Connector Card ───────────────────────────────────────────────────────────

class _ConnectorCard extends StatelessWidget {
  final ConnectorState connectorState;
  final CpProvider provider;

  const _ConnectorCard({required this.connectorState, required this.provider});

  @override
  Widget build(BuildContext context) {
    final c     = connectorState;
    final color = AppTheme.statusColor(c.status.name);
    final isCharging = c.isCharging;

    return CardContainer(
      borderColor: isCharging ? AppTheme.charging.withValues(alpha: 0.4) : AppTheme.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '${c.connectorId}',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Connector ${c.connectorId}',
                      style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                    StatusPill(label: c.status.name.toUpperCase(), color: color, fontSize: 10),
                  ],
                ),
              ),
              // Live power badge
              if (isCharging && c.powerW != null)
                _LiveBadge('${(c.powerW! / 1000).toStringAsFixed(1)} kW'),
            ],
          ),

          // ── Active session details ───────────────────────────────────────
          if (isCharging) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _SessionMetrics(c: c),
          ],

          // ── Session timer ticker ─────────────────────────────────────────
          if (isCharging) ...[
            const SizedBox(height: 10),
            _SessionTimer(startTime: c.sessionStartTime!),
          ],

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // ── Action row ───────────────────────────────────────────────────
          _ConnectorActions(c: c, provider: provider),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  final String label;
  const _LiveBadge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.charging.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.charging.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.charging),
          ),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: AppTheme.charging, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _SessionMetrics extends StatelessWidget {
  final ConnectorState c;
  const _SessionMetrics({required this.c});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Metric('Energy', '${c.energyDeliveredKwh.toStringAsFixed(3)} kWh', AppTheme.charging),
        _Metric('Power',  c.powerW != null ? '${(c.powerW! / 1000).toStringAsFixed(2)} kW' : '—', AppTheme.info),
        _Metric('Voltage', c.voltageV != null ? '${c.voltageV!.toStringAsFixed(0)} V' : '—', AppTheme.warning),
        _Metric('Current', c.currentA != null ? '${c.currentA!.toStringAsFixed(1)} A' : '—', AppTheme.preparing),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Metric(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }
}

class _SessionTimer extends StatefulWidget {
  final DateTime startTime;
  const _SessionTimer({required this.startTime});

  @override
  State<_SessionTimer> createState() => _SessionTimerState();
}

class _SessionTimerState extends State<_SessionTimer> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dur = DateTime.now().difference(widget.startTime);
    final h = dur.inHours.toString().padLeft(2, '0');
    final m = (dur.inMinutes % 60).toString().padLeft(2, '0');
    final s = (dur.inSeconds % 60).toString().padLeft(2, '0');

    return Row(
      children: [
        const Icon(Icons.timer_outlined, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Text('Session: $h:$m:$s',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        const Spacer(),
      ],
    );
  }
}

class _ConnectorActions extends StatelessWidget {
  final ConnectorState c;
  final CpProvider provider;
  const _ConnectorActions({required this.c, required this.provider});

  @override
  Widget build(BuildContext context) {
    final bool canStart  = c.phase == SimulatorPhase.idle &&
                           c.status == ConnectorStatus.Available &&
                           provider.isBooted;
    final bool canStop   = c.isCharging;

    if (!provider.isBooted) {
      return const Text('Boot the charge point to use connectors',
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12));
    }

    return Row(
      children: [
        if (canStart) ...[
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _showStartDialog(context),
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('Start Session'),
            ),
          ),
        ],
        if (canStop) ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => provider.stopSession(c.connectorId),
              icon: const Icon(Icons.stop, size: 16),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.error,
                side: const BorderSide(color: AppTheme.error),
              ),
              label: const Text('Stop Session'),
            ),
          ),
        ],
        if (!canStart && !canStop) ...[
          Expanded(
            child: Text(
              c.status == ConnectorStatus.Unavailable ? 'Connector Unavailable' :
              c.phase == SimulatorPhase.preparing ? 'Authorizing...' :
              c.phase == SimulatorPhase.finishing ? 'Finishing...' : c.status.name,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showStartDialog(BuildContext context) async {
    final ctrl = TextEditingController(text: 'TAG-001');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        title: Text('Start Session — Connector ${c.connectorId}'),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: 'ID Tag (RFID)',
            prefixIcon: Icon(Icons.nfc, color: AppTheme.textSecondary, size: 18),
            hintText: 'e.g. TAG-001',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      final success = await provider.startSession(c.connectorId, ctrl.text.trim());
      if (!success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authorization failed — tag not accepted'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
    ctrl.dispose();
  }
}
