// lib/screens/charge_point_detail_screen.dart
// Full detail view for a single charge point.
// Shows connector status and all available remote commands.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/csms_provider.dart';
import '../models/csms_models.dart';
import '../utils/app_theme.dart';
import '../widgets/shared_widgets.dart';

class ChargePointDetailScreen extends StatelessWidget {
  final String cpId;
  const ChargePointDetailScreen({super.key, required this.cpId});

  @override
  Widget build(BuildContext context) {
    return Consumer<CsmsProvider>(
      builder: (context, provider, _) {
        final cp = provider.chargePoints.firstWhere(
          (c) => c.chargePointId == cpId,
          orElse: () => ChargePointModel(
            chargePointId: cpId, vendor: '', model: '',
            serialNumber: '', firmwareVersion: '',
            isOnline: false, connectors: [],
          ),
        );

        return Scaffold(
          backgroundColor: AppTheme.surface,
          appBar: AppBar(
            title: Row(
              children: [
                OnlineDot(isOnline: cp.isOnline),
                const SizedBox(width: 8),
                Text(cpId),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_remote),
                tooltip: 'Remote Commands',
                onPressed: () => _showCommandPanel(context, provider, cp),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── CP Info card ───────────────────────────────────────────────
              _InfoCard(cp: cp),
              const SizedBox(height: 16),

              // ── Connectors ─────────────────────────────────────────────────
              const SectionHeader(title: 'CONNECTORS'),
              const SizedBox(height: 10),
              if (cp.connectors.isEmpty)
                const EmptyState(
                  icon: Icons.power_outlined,
                  title: 'No connectors registered yet',
                  subtitle: 'Connectors appear after the first StatusNotification',
                )
              else
                ...cp.connectors.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ConnectorDetailCard(
                    connector: c,
                    cp: cp,
                    provider: provider,
                    activeTx: provider.activeTransactions
                        .where((t) => t.chargePointId == cpId && t.connectorNumber == c.connectorId)
                        .firstOrNull,
                  ),
                )),

              const SizedBox(height: 16),

              // ── Quick Actions ──────────────────────────────────────────────
              const SectionHeader(title: 'QUICK ACTIONS'),
              const SizedBox(height: 10),
              _QuickActions(cp: cp, provider: provider),
            ],
          ),
        );
      },
    );
  }

  void _showCommandPanel(BuildContext context, CsmsProvider provider, ChargePointModel cp) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RemoteCommandSheet(cp: cp, provider: provider),
    );
  }
}

// ─── Info Card ────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final ChargePointModel cp;
  const _InfoCard({required this.cp});

  @override
  Widget build(BuildContext context) {
    final bootStr = cp.lastBootTime != null
        ? DateFormat('dd MMM yyyy HH:mm').format(cp.lastBootTime!.toLocal())
        : '—';
    final hbStr = cp.lastHeartbeat != null
        ? DateFormat('HH:mm:ss').format(cp.lastHeartbeat!.toLocal())
        : '—';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          _InfoRow('Vendor',    cp.vendor.isEmpty ? '—' : cp.vendor),
          _InfoRow('Model',     cp.model.isEmpty ? '—' : cp.model),
          _InfoRow('Serial',    cp.serialNumber.isEmpty ? '—' : cp.serialNumber),
          _InfoRow('Firmware',  cp.firmwareVersion.isEmpty ? '—' : cp.firmwareVersion),
          _InfoRow('Last Boot', bootStr),
          _InfoRow('Heartbeat', hbStr, isLast: true),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;
  const _InfoRow(this.label, this.value, {this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              const Spacer(),
              Text(value, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            ],
          ),
        ),
        if (!isLast) const Divider(height: 1),
      ],
    );
  }
}

// ─── Connector Detail Card ────────────────────────────────────────────────────

class _ConnectorDetailCard extends StatefulWidget {
  final ConnectorModel connector;
  final ChargePointModel cp;
  final CsmsProvider provider;
  final TransactionModel? activeTx;
  const _ConnectorDetailCard({
    required this.connector,
    required this.cp,
    required this.provider,
    this.activeTx,
  });

  @override
  State<_ConnectorDetailCard> createState() => _ConnectorDetailCardState();
}

class _ConnectorDetailCardState extends State<_ConnectorDetailCard> {
  final _tagController = TextEditingController(text: 'TAG-001');
  bool _loading = false;
  StreamSubscription? _authSub;

  @override
  void dispose() {
    _authSub?.cancel();
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c     = widget.connector;
    final tx    = widget.activeTx;
    final color = AppTheme.statusColor(c.status);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: c.isCharging ? color.withValues(alpha: 0.4) : AppTheme.border,
          width: c.isCharging ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    c.isCharging ? Icons.bolt : Icons.ev_station_outlined,
                    color: color, size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connector ${c.connectorId}',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600, fontSize: 14,
                        ),
                      ),
                      if (tx != null)
                        Text(
                          'Tag: ${tx.idTag}  ·  TX #${tx.transactionId}',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                        )
                      else if (c.errorCode != 'NoError')
                        Text(
                          '⚠ ${c.errorCode}',
                          style: const TextStyle(color: AppTheme.error, fontSize: 11),
                        ),
                    ],
                  ),
                ),
                StatusPill(label: c.status, color: color),
              ],
            ),
          ),

          // Live metrics if charging
          if (tx != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    MetricTile(label: 'Power', value: '${tx.powerKw.toStringAsFixed(1)} kW', color: AppTheme.charging),
                    Container(width: 1, height: 28, color: AppTheme.border),
                    MetricTile(label: 'Energy', value: '${tx.energyKwh.toStringAsFixed(3)} kWh', color: AppTheme.info),
                    Container(width: 1, height: 28, color: AppTheme.border),
                    MetricTile(
                      label: 'Elapsed',
                      value: _formatDuration(tx.elapsed),
                      color: AppTheme.warning,
                    ),
                  ],
                ),
              ),
            ),
            // Mini power chart
            if (tx.powerHistory.length >= 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: SizedBox(
                  height: 60,
                  child: _PowerChart(history: tx.powerHistory),
                ),
              ),
          ],

          // Controls
          Padding(
            padding: const EdgeInsets.all(14),
            child: _buildControls(),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final c  = widget.connector;
    final tx = widget.activeTx;

    if (c.isCharging && tx != null) {
      // Active session — show stop button
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _loading ? null : () => _stop(tx),
          icon: _loading
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.error))
              : const Icon(Icons.stop, size: 16),
          label: const Text('Stop Session'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.error,
            side: const BorderSide(color: AppTheme.error),
          ),
        ),
      );
    }

    if (c.isAvailable) {
      // Available — show remote start
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: _tagController,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'RFID / ID Tag',
                prefixIcon: Icon(Icons.nfc, color: AppTheme.textSecondary, size: 18),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 42,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _start,
              icon: _loading
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.surface))
                  : const Icon(Icons.play_arrow, size: 16),
              label: const Text('Start'),
            ),
          ),
        ],
      );
    }

    // Unavailable / Faulted — show availability toggle
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => widget.provider.changeAvailability(
              widget.cp.chargePointId, c.connectorId, 'Operative',
            ),
            icon: const Icon(Icons.power_settings_new, size: 16),
            label: const Text('Set Operative'),
          ),
        ),
      ],
    );
  }

  Future<void> _start() async {
    final tag = _tagController.text.trim();
    if (tag.isEmpty) return;
    setState(() => _loading = true);

    // Listen for the authorize result that comes back async from the CP
    _authSub?.cancel();
    _authSub = widget.provider.authResultStream
        .where((d) => d['idTag'] == tag && d['chargePointId'] == widget.cp.chargePointId)
        .timeout(const Duration(seconds: 10))
        .take(1)
        .listen(
          (d) {
            if (!mounted) return;
            final authStatus = d['status'] as String? ?? '';
            final (ok, message) = _interpretRemoteStartResult(authStatus);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Row(children: [
                Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
                    color: AppTheme.surface, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ]),
              backgroundColor: ok ? AppTheme.available : AppTheme.error,
              duration: const Duration(seconds: 4),
            ));
          },
          onError: (_) {
            // Timeout — CP didn't respond in time
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No response from charge point — check connection'),
              backgroundColor: AppTheme.error,
            ));
          },
        );

    try {
      await widget.provider.remoteStart(
        widget.cp.chargePointId,
        tag,
        widget.connector.connectorId,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  (bool, String) _interpretRemoteStartResult(dynamic result) {
    // result is the status string returned by remoteStart e.g. 'Accepted', 'Rejected'
    // The CP's StartTransaction response idTagInfo.status reveals auth failure detail
    final status = result?.toString() ?? '';
    return switch (status) {
      'Accepted'          => (true,  'Session started successfully'),
      'Rejected'          => (false, 'Rejected — connector may be busy or unavailable'),
      'Invalid'           => (false, 'Unauthorised — tag "${ _tagController.text.trim()}" is not registered'),
      'Blocked'           => (false, 'Tag blocked — this RFID card has been suspended'),
      'Expired'           => (false, 'Tag expired — RFID card validity has lapsed'),
      'ConcurrentTx'      => (false, 'Concurrent transaction — tag already has an active session'),
      'Sent'              => (true,  'Command sent to charge point'),
      _                   => (false, 'Unknown response: $status — check OCPP logs'),
    };
  }

  Future<void> _stop(TransactionModel tx) async {
    setState(() => _loading = true);
    try {
      await widget.provider.remoteStop(widget.cp.chargePointId, tx.transactionId);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDuration(Duration d) =>
      '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

// ─── Power Chart ──────────────────────────────────────────────────────────────

class _PowerChart extends StatelessWidget {
  final List<double> history;
  const _PowerChart({required this.history});

  @override
  Widget build(BuildContext context) {
    final spots = history.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();
    final maxY = history.reduce((a, b) => a > b ? a : b) + 1;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true, drawVerticalLine: false,
          horizontalInterval: maxY / 2,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppTheme.border, strokeWidth: 0.5),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: maxY / 2,
              getTitlesWidget: (v, _) => Text(
                '${v.toStringAsFixed(0)}kW',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 8),
              ),
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: 0, maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppTheme.charging,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.charging.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 100),
    );
  }
}

// ─── Quick Actions ────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  final ChargePointModel cp;
  final CsmsProvider provider;
  const _QuickActions({required this.cp, required this.provider});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 3,
      children: [
        _ActionButton(
          label: 'Soft Reset',
          icon: Icons.restart_alt,
          color: AppTheme.warning,
          onTap: () => _confirmReset(context, 'Soft'),
        ),
        _ActionButton(
          label: 'Hard Reset',
          icon: Icons.power_off,
          color: AppTheme.error,
          onTap: () => _confirmReset(context, 'Hard'),
        ),
        _ActionButton(
          label: 'Clear Cache',
          icon: Icons.cleaning_services_outlined,
          color: AppTheme.info,
          onTap: () => provider.clearCache(cp.chargePointId),
        ),
        _ActionButton(
          label: 'Trigger Status',
          icon: Icons.refresh,
          color: AppTheme.primary,
          onTap: () => provider.triggerMessage(cp.chargePointId, 'StatusNotification', null),
        ),
      ],
    );
  }

  void _confirmReset(BuildContext context, String type) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        title: Text('$type Reset', style: const TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          type == 'Hard'
              ? 'Hard reset immediately restarts the CP and may interrupt active sessions.'
              : 'Soft reset will restart the CP gracefully after finishing active sessions.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              provider.resetCp(cp.chargePointId, type);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: type == 'Hard' ? AppTheme.error : AppTheme.warning,
            ),
            child: Text('$type Reset'),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─── Remote Command Sheet (bottom sheet with all OCPP commands) ───────────────

class _RemoteCommandSheet extends StatefulWidget {
  final ChargePointModel cp;
  final CsmsProvider provider;
  const _RemoteCommandSheet({required this.cp, required this.provider});

  @override
  State<_RemoteCommandSheet> createState() => _RemoteCommandSheetState();
}

class _RemoteCommandSheetState extends State<_RemoteCommandSheet> {
  final _tagCtrl       = TextEditingController(text: 'TAG-001');
  final _connCtrl      = TextEditingController(text: '1');
  final _configKeyCtrl = TextEditingController(text: 'HeartbeatInterval');
  final _configValCtrl = TextEditingController(text: '30');

  @override
  void dispose() {
    _tagCtrl.dispose();
    _connCtrl.dispose();
    _configKeyCtrl.dispose();
    _configValCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Remote Commands',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 17, fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(label: widget.cp.chargePointId, color: AppTheme.primary),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _CommandSection(
                    title: 'SESSION CONTROL',
                    children: [
                      _CommandRow(
                        label: 'Remote Start',
                        icon: Icons.play_arrow,
                        color: AppTheme.charging,
                        fields: [
                          _FieldInput(ctrl: _tagCtrl,  label: 'Tag ID'),
                          _FieldInput(ctrl: _connCtrl, label: 'Connector'),
                        ],
                        onSend: () async {
                          final result = await widget.provider.remoteStart(
                            widget.cp.chargePointId,
                            _tagCtrl.text.trim(),
                            int.tryParse(_connCtrl.text),
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          final status = result?.toString() ?? '';
                          final ok      = status == 'Accepted';
                          final message = switch (status) {
                            'Accepted'     => 'Session started on connector ${_connCtrl.text}',
                            'Rejected'     => 'Rejected — connector busy or unavailable',
                            'Invalid'      => 'Unauthorised — tag "${_tagCtrl.text.trim()}" is not registered',
                            'Blocked'      => 'Tag blocked — RFID card has been suspended',
                            'Expired'      => 'Tag expired — RFID card validity has lapsed',
                            'ConcurrentTx' => 'Tag already has an active session elsewhere',
                            'Sent'         => 'Command sent to charge point',
                            _              => 'Unknown response: $status',
                          };
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(message),
                              backgroundColor: ok ? AppTheme.available : AppTheme.error,
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  _CommandSection(
                    title: 'AVAILABILITY',
                    children: [
                      _SimpleCommand(
                        label: 'Set Operative (all connectors)',
                        icon: Icons.check_circle_outline,
                        color: AppTheme.available,
                        onTap: () {
                          widget.provider.changeAvailability(widget.cp.chargePointId, 0, 'Operative');
                          Navigator.pop(context);
                        },
                      ),
                      _SimpleCommand(
                        label: 'Set Inoperative (all connectors)',
                        icon: Icons.cancel_outlined,
                        color: AppTheme.warning,
                        onTap: () {
                          widget.provider.changeAvailability(widget.cp.chargePointId, 0, 'Inoperative');
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                  _CommandSection(
                    title: 'CONFIGURATION',
                    children: [
                      _CommandRow(
                        label: 'Change Config',
                        icon: Icons.tune,
                        color: AppTheme.info,
                        fields: [
                          _FieldInput(ctrl: _configKeyCtrl, label: 'Key'),
                          _FieldInput(ctrl: _configValCtrl, label: 'Value'),
                        ],
                        onSend: () async {
                          widget.provider.triggerMessage(
                            widget.cp.chargePointId,
                            'GetConfiguration',
                            null,
                          );
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                  _CommandSection(
                    title: 'MAINTENANCE',
                    children: [
                      _SimpleCommand(
                        label: 'Soft Reset',
                        icon: Icons.restart_alt,
                        color: AppTheme.warning,
                        onTap: () {
                          widget.provider.resetCp(widget.cp.chargePointId, 'Soft');
                          Navigator.pop(context);
                        },
                      ),
                      _SimpleCommand(
                        label: 'Hard Reset',
                        icon: Icons.power_off,
                        color: AppTheme.error,
                        onTap: () {
                          widget.provider.resetCp(widget.cp.chargePointId, 'Hard');
                          Navigator.pop(context);
                        },
                      ),
                      _SimpleCommand(
                        label: 'Clear Cache',
                        icon: Icons.cleaning_services_outlined,
                        color: AppTheme.info,
                        onTap: () {
                          widget.provider.clearCache(widget.cp.chargePointId);
                          Navigator.pop(context);
                        },
                      ),
                      _SimpleCommand(
                        label: 'Trigger StatusNotification',
                        icon: Icons.refresh,
                        color: AppTheme.primary,
                        onTap: () {
                          widget.provider.triggerMessage(widget.cp.chargePointId, 'StatusNotification', null);
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _CommandSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 1.2,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

class _SimpleCommand extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _SimpleCommand({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
      title: Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
      trailing: const Icon(Icons.send, color: AppTheme.textSecondary, size: 16),
      onTap: onTap,
    );
  }
}

class _FieldInput {
  final TextEditingController ctrl;
  final String label;
  const _FieldInput({required this.ctrl, required this.label});
}

class _CommandRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final List<_FieldInput> fields;
  final Future<void> Function() onSend;
  const _CommandRow({
    required this.label, required this.icon, required this.color,
    required this.fields, required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ...fields.map((f) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: f == fields.last ? 0 : 8),
                child: TextField(
                  controller: f.ctrl,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: f.label,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
            )),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: onSend,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: const Text('Send'),
            ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
