// lib/screens/dashboard_screen.dart
// Overview screen — shows live stats, all charge points, active sessions.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/csms_provider.dart';
import '../models/csms_models.dart';
import '../utils/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'charge_point_detail_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CsmsProvider>(
      builder: (context, provider, _) {
        return RefreshIndicator(
          color: AppTheme.primary,
          backgroundColor: AppTheme.surfaceCard,
          onRefresh: () async {
            if (provider.isConnected) {
              await provider.loadInitialData();
            }
          },
          child: CustomScrollView(
            slivers: [
              // ── Stats row ─────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _StatsGrid(stats: provider.stats),
                ),
              ),

              // ── Active Sessions ───────────────────────────────────────────
              if (provider.activeTransactions.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
                    child: SectionHeader(
                      title: 'ACTIVE SESSIONS',
                      trailing: StatusPill(
                        label: '${provider.activeTransactions.length}',
                        color: AppTheme.charging,
                      ),
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: _ActiveSessionCard(tx: provider.activeTransactions[i], provider: provider),
                    ),
                    childCount: provider.activeTransactions.length,
                  ),
                ),
              ],

              // ── Charge Points ─────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
                  child: SectionHeader(
                    title: 'CHARGE POINTS',
                    trailing: StatusPill(
                      label: '${provider.stats.onlineChargePoints}/${provider.stats.totalChargePoints} online',
                      color: AppTheme.available,
                    ),
                  ),
                ),
              ),

              if (provider.chargePoints.isEmpty)
                const SliverFillRemaining(
                  child: EmptyState(
                    icon: Icons.ev_station_outlined,
                    title: 'No charge points registered',
                    subtitle: 'Charge points appear here when they send a BootNotification',
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: _ChargePointCard(cp: provider.chargePoints[i]),
                    ),
                    childCount: provider.chargePoints.length,
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

// ─── Stats Grid ───────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final DashboardStats stats;
  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.4,
      children: [
        StatCard(
          label: 'Online CPs',
          value: '${stats.onlineChargePoints}',
          color: AppTheme.available,
          icon: Icons.ev_station,
        ),
        StatCard(
          label: 'Active Sessions',
          value: '${stats.activeSessions}',
          color: AppTheme.charging,
          icon: Icons.bolt,
        ),
        StatCard(
          label: 'Available',
          value: '${stats.availableConnectors}',
          color: AppTheme.info,
          icon: Icons.check_circle_outline,
        ),
        StatCard(
          label: 'Faulted',
          value: '${stats.faultedConnectors}',
          color: stats.faultedConnectors > 0 ? AppTheme.error : AppTheme.textSecondary,
          icon: Icons.warning_amber_outlined,
        ),
      ],
    );
  }
}

// ─── Active Session Card ──────────────────────────────────────────────────────

class _ActiveSessionCard extends StatelessWidget {
  final TransactionModel tx;
  final CsmsProvider provider;
  const _ActiveSessionCard({required this.tx, required this.provider});

  @override
  Widget build(BuildContext context) {
    final dur = tx.elapsed;
    final durStr =
        '${dur.inHours.toString().padLeft(2, '0')}:${(dur.inMinutes % 60).toString().padLeft(2, '0')}:${(dur.inSeconds % 60).toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.charging.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.charging.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.bolt, color: AppTheme.charging, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${tx.chargePointId} · Connector ${tx.connectorNumber}',
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    Text(
                      'Tag: ${tx.idTag}  ·  TX #${tx.transactionId}',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              // Stop button
              OutlinedButton(
                onPressed: () => _confirmStop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  side: const BorderSide(color: AppTheme.error),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Stop', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Metrics row
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                MetricTile(
                  label: 'Power',
                  value: '${tx.powerKw.toStringAsFixed(1)} kW',
                  color: AppTheme.charging,
                  icon: Icons.bolt,
                ),
                Container(width: 1, height: 28, color: AppTheme.border),
                MetricTile(
                  label: 'Energy',
                  value: '${tx.energyKwh.toStringAsFixed(3)} kWh',
                  color: AppTheme.info,
                  icon: Icons.battery_charging_full,
                ),
                Container(width: 1, height: 28, color: AppTheme.border),
                MetricTile(
                  label: 'Duration',
                  value: durStr,
                  color: AppTheme.warning,
                  icon: Icons.timer_outlined,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmStop(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Stop Session', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Stop transaction #${tx.transactionId} on ${tx.chargePointId}?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              provider.remoteStop(tx.chargePointId, tx.transactionId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}

// ─── Charge Point Card ────────────────────────────────────────────────────────

class _ChargePointCard extends StatelessWidget {
  final ChargePointModel cp;
  const _ChargePointCard({required this.cp});

  @override
  Widget build(BuildContext context) {
    final hbStr = cp.lastHeartbeat != null
        ? DateFormat('HH:mm:ss').format(cp.lastHeartbeat!.toLocal())
        : '—';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChargePointDetailScreen(cpId: cp.chargePointId)),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cp.isOnline ? AppTheme.border : AppTheme.border.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                OnlineDot(isOnline: cp.isOnline),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cp.chargePointId,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '${cp.vendor} ${cp.model}'.trim().isEmpty
                            ? 'Unknown device'
                            : '${cp.vendor} ${cp.model}'.trim(),
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Hb $hbStr',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 18),
              ],
            ),
            // Connectors
            if (cp.connectors.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: cp.connectors.map((c) {
                  final color = AppTheme.statusColor(c.status);
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.only(
                        right: cp.connectors.last == c ? 0 : 6,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            c.isCharging ? Icons.bolt : Icons.ev_station_outlined,
                            color: color,
                            size: 16,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'C${c.connectorId}',
                            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            c.status,
                            style: TextStyle(color: color, fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}