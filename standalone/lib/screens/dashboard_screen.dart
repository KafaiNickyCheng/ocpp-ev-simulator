// lib/screens/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ocpp_models.dart';
import '../providers/charge_point_provider.dart';
import '../utils/app_theme.dart';
import '../widgets/connector_card.dart';
import '../widgets/status_badge.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChargePointProvider>(
      builder: (context, provider, _) {
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(context, provider)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ConnectorCard(connector: provider.connectors[i]),
                  ),
                  childCount: provider.connectors.length,
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildStatsRow(context, provider)),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, ChargePointProvider provider) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.surfaceCard,
            AppTheme.primary.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.ev_station, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.config.chargePointId,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${provider.config.vendor} · ${provider.config.model}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _ConnectionBadge(state: provider.connectionState),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              _InfoChip(
                icon: Icons.electrical_services,
                label: 'OCPP',
                value: provider.config.ocppVersion == OcppVersion.ocpp16 ? '1.6' : '2.0.1',
              ),
              const SizedBox(width: 8),
              _InfoChip(
                icon: Icons.power,
                label: 'Max Power',
                value: '${provider.config.maxPowerKw.toStringAsFixed(0)} kW',
              ),
              const SizedBox(width: 8),
              _InfoChip(
                icon: Icons.cable,
                label: 'Connectors',
                value: '${provider.config.numberOfConnectors}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildConnectButton(context, provider),
        ],
      ),
    );
  }

  Widget _buildConnectButton(BuildContext context, ChargePointProvider provider) {
    final isConnected = provider.connectionState == CpConnectionState.connected;
    final isConnecting = provider.connectionState == CpConnectionState.connecting;

    return SizedBox(
      width: double.infinity,
      child: isConnected
          ? OutlinedButton.icon(
              onPressed: provider.disconnect,
              icon: const Icon(Icons.link_off, size: 18),
              label: const Text('Disconnect from Central System'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.error,
                side: const BorderSide(color: AppTheme.error),
              ),
            )
          : ElevatedButton.icon(
              onPressed: isConnecting ? null : provider.connect,
              icon: isConnecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.surface),
                    )
                  : const Icon(Icons.link, size: 18),
              label: Text(isConnecting ? 'Connecting…' : 'Connect to Central System'),
            ),
    );
  }

  Widget _buildStatsRow(BuildContext context, ChargePointProvider provider) {
    final activeCharging = provider.connectors
        .where((c) => c.activeTransactionId != null)
        .length;
    final totalEnergy = provider.connectors
        .fold(0.0, (sum, c) => sum + c.energyDeliveredKwh);
    final totalPower = provider.connectors
        .fold(0.0, (sum, c) => sum + c.currentPowerKw);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              icon: Icons.bolt,
              label: 'Active Sessions',
              value: '$activeCharging',
              color: AppTheme.charging,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              icon: Icons.electric_meter,
              label: 'Total Energy',
              value: '${totalEnergy.toStringAsFixed(2)} kWh',
              color: AppTheme.info,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              icon: Icons.power,
              label: 'Total Power',
              value: '${totalPower.toStringAsFixed(1)} kW',
              color: AppTheme.warning,
            ),
          ),
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
        color = AppTheme.available;
        label = 'Connected';
        break;
      case CpConnectionState.connecting:
        color = AppTheme.warning;
        label = 'Connecting';
        break;
      case CpConnectionState.reconnecting:
        color = AppTheme.warning;
        label = 'Reconnecting';
        break;
      default:
        color = AppTheme.textSecondary;
        label = 'Offline';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoChip({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          Text(value,
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}