// lib/widgets/connector_card.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../models/ocpp_models.dart';
import '../providers/charge_point_provider.dart';
import '../utils/app_theme.dart';

class ConnectorCard extends StatefulWidget {
  final ConnectorModel connector;
  const ConnectorCard({super.key, required this.connector});

  @override
  State<ConnectorCard> createState() => _ConnectorCardState();
}

class _ConnectorCardState extends State<ConnectorCard> {
  final _idTagController = TextEditingController(text: 'TAG-001');
  bool _isProcessing = false;

  @override
  void dispose() {
    _idTagController.dispose();
    super.dispose();
  }

  Color get _statusColor {
    switch (widget.connector.status) {
      case ConnectorStatus.available:
        return AppTheme.available;
      case ConnectorStatus.occupied:
        return AppTheme.charging;
      case ConnectorStatus.reserved:
        return AppTheme.warning;
      case ConnectorStatus.unavailable:
        return AppTheme.unavailable;
      case ConnectorStatus.faulted:
        return AppTheme.faulted;
    }
  }

  String get _statusLabel {
    switch (widget.connector.status) {
      case ConnectorStatus.available:
        return 'Available';
      case ConnectorStatus.occupied:
        return 'Charging';
      case ConnectorStatus.reserved:
        return 'Reserved';
      case ConnectorStatus.unavailable:
        return 'Unavailable';
      case ConnectorStatus.faulted:
        return 'Faulted';
    }
  }

  bool get _isCharging => widget.connector.activeTransactionId != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isCharging ? _statusColor.withValues(alpha: 0.4) : AppTheme.border,
          width: _isCharging ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (_isCharging) ...[
            _buildChargingInfo(),
            _buildPowerChart(),
          ],
          _buildControls(context),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _isCharging ? Icons.bolt : Icons.ev_station_outlined,
              color: _statusColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connector ${widget.connector.id}',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                if (widget.connector.authorizedIdTag != null)
                  Text(
                    'ID: ${widget.connector.authorizedIdTag}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          _StatusPill(label: _statusLabel, color: _statusColor),
        ],
      ),
    );
  }

  Widget _buildChargingInfo() {
    final dur = widget.connector.sessionDuration;
    final durStr =
        '${dur.inHours.toString().padLeft(2, '0')}:${(dur.inMinutes % 60).toString().padLeft(2, '0')}:${(dur.inSeconds % 60).toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          _MetricTile(
            label: 'Power',
            value: '${widget.connector.currentPowerKw.toStringAsFixed(1)} kW',
            color: AppTheme.charging,
          ),
          _Divider(),
          _MetricTile(
            label: 'Energy',
            value: '${widget.connector.energyDeliveredKwh.toStringAsFixed(3)} kWh',
            color: AppTheme.info,
          ),
          _Divider(),
          _MetricTile(
            label: 'Duration',
            value: durStr,
            color: AppTheme.warning,
          ),
          _Divider(),
          _MetricTile(
            label: 'Est. Cost',
            value: '\$${widget.connector.sessionCostEstimate.toStringAsFixed(2)}',
            color: AppTheme.available,
          ),
        ],
      ),
    );
  }

  Widget _buildPowerChart() {
    final history = widget.connector.meterHistory;
    if (history.length < 2) return const SizedBox(height: 8);

    final spots = history.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.powerKw);
    }).toList();

    final maxY = history.map((s) => s.powerKw).reduce((a, b) => a > b ? a : b) + 2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SizedBox(
        height: 80,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxY / 4,
              getDrawingHorizontalLine: (_) => FlLine(
                color: AppTheme.border,
                strokeWidth: 0.5,
              ),
            ),
            titlesData: FlTitlesData(
              show: true,
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  interval: maxY / 2,
                  getTitlesWidget: (v, _) => Text(
                    '${v.toStringAsFixed(0)}kW',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 9),
                  ),
                ),
              ),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            minY: 0,
            maxY: maxY,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: AppTheme.charging,
                barWidth: 2,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppTheme.charging.withValues(alpha: 0.1),
                ),
              ),
            ],
          ),
          duration: const Duration(milliseconds: 100),
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final provider = context.read<ChargePointProvider>();
    final isConnected = provider.connectionState == CpConnectionState.connected;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (!_isCharging) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _idTagController,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'RFID / ID Tag',
                      prefixIcon:
                          Icon(Icons.nfc, color: AppTheme.textSecondary, size: 18),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 42,
                  child: ElevatedButton.icon(
                    onPressed: isConnected && !_isProcessing
                        ? () => _startSession(provider)
                        : null,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.surface),
                          )
                        : const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Start'),
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isConnected
                        ? () => _stopSession(provider)
                        : null,
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Stop Session'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      side: const BorderSide(color: AppTheme.error),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: isConnected
                      ? () => _simulateFault(context, provider)
                      : null,
                  icon: const Icon(Icons.warning_amber, size: 16),
                  label: const Text('Fault'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.warning,
                    side: const BorderSide(color: AppTheme.warning),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _startSession(ChargePointProvider provider) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final success = await provider.startTransaction(
          widget.connector.id, _idTagController.text.trim());
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authorization failed or connector busy'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _stopSession(ChargePointProvider provider) async {
    await provider.stopTransaction(widget.connector.id);
  }

  void _simulateFault(BuildContext context, ChargePointProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FaultSheet(
        connectorId: widget.connector.id,
        provider: provider,
      ),
    );
  }
}

class _FaultSheet extends StatelessWidget {
  final int connectorId;
  final ChargePointProvider provider;
  const _FaultSheet({required this.connectorId, required this.provider});

  @override
  Widget build(BuildContext context) {
    final faults = [
      (ChargePointErrorCode.evCommunicationError, 'EV Communication Error'),
      (ChargePointErrorCode.groundFailure, 'Ground Failure'),
      (ChargePointErrorCode.highTemperature, 'High Temperature'),
      (ChargePointErrorCode.overCurrentFailure, 'Over Current Failure'),
      (ChargePointErrorCode.overVoltage, 'Over Voltage'),
      (ChargePointErrorCode.underVoltage, 'Under Voltage'),
      (ChargePointErrorCode.powerMeterFailure, 'Power Meter Failure'),
    ];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Simulate Fault',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Select an error to send StatusNotification',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          ...faults.map((f) => ListTile(
                dense: true,
                leading: const Icon(Icons.error_outline, color: AppTheme.error, size: 20),
                title: Text(f.$2,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                onTap: () {
                  Navigator.pop(context);
                  provider.simulateFault(connectorId, f.$1);
                },
                contentPadding: EdgeInsets.zero,
              )),
          const Divider(),
          ListTile(
            dense: true,
            leading: const Icon(Icons.check_circle_outline,
                color: AppTheme.available, size: 20),
            title: const Text('Clear Fault',
                style: TextStyle(color: AppTheme.available, fontSize: 14)),
            onTap: () {
              Navigator.pop(context);
              provider.clearFault(connectorId);
            },
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700,
              letterSpacing: 0.3)),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MetricTile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 30, color: AppTheme.border);
  }
}