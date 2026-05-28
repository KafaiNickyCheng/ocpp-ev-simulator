// lib/screens/remote_screen.dart
// Simulates the CSMS side — inject remote commands into the CP mock

import '../models/ocpp_models.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/charge_point_provider.dart';
import '../utils/app_theme.dart';

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  final _remoteIdTagCtrl = TextEditingController(text: 'REMOTE-TAG');
  int _selectedConnector = 1;
  String? _lastResult;

  @override
  void dispose() {
    _remoteIdTagCtrl.dispose();
    super.dispose();
  }

  void _inject(BuildContext context, String action, Map<String, dynamic> payload) {
    final provider = context.read<ChargePointProvider>();
    if (provider.connectionState != CpConnectionState.connected) {
      setState(() => _lastResult = '⚠ Not connected to CSMS');
      return;
    }
    provider.injectRemoteCommand(action, payload);
    setState(() => _lastResult = '✓ Sent $action to CP');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChargePointProvider>(
      builder: (context, provider, _) {
        final isConnected =
            provider.connectionState == CpConnectionState.connected;
        final connectors = provider.connectors;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(),
              if (!isConnected)
                _NotConnectedBanner(),
              if (_lastResult != null)
                _ResultBanner(_lastResult!),
              const SizedBox(height: 4),

              // ── Connector selector ──────────────────────────────────
              _SectionLabel('Target Connector'),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: connectors.map((c) {
                    final selected = _selectedConnector == c.id;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedConnector = c.id),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primary.withValues(alpha: 0.15)
                              : AppTheme.surfaceCard,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected
                                ? AppTheme.primary.withValues(alpha: 0.5)
                                : AppTheme.border,
                          ),
                        ),
                        child: Text(
                          'Connector ${c.id}',
                          style: TextStyle(
                            color: selected
                                ? AppTheme.primary
                                : AppTheme.textSecondary,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),

              // ── Remote Start ────────────────────────────────────────
              _SectionLabel('Transaction Control'),
              _CommandCard(
                icon: Icons.play_circle_outline,
                title: 'RemoteStartTransaction',
                description:
                    'CSMS instructs the CP to start a charging session.',
                color: AppTheme.available,
                enabled: isConnected,
                children: [
                  _TagField(controller: _remoteIdTagCtrl),
                ],
                onSend: () => _inject(context, 'RemoteStartTransaction', {
                  'connectorId': _selectedConnector,
                  'idTag': _remoteIdTagCtrl.text.trim(),
                }),
              ),
              const SizedBox(height: 12),

              // ── Remote Stop ─────────────────────────────────────────
              _CommandCard(
                icon: Icons.stop_circle_outlined,
                title: 'RemoteStopTransaction',
                description:
                    'CSMS instructs the CP to stop an active session.',
                color: AppTheme.error,
                enabled: isConnected,
                children: [
                  _TxIdPicker(
                    connectors: provider.connectors,
                    onSelect: (txId, connId) => _inject(
                      context,
                      'RemoteStopTransaction',
                      {'transactionId': int.tryParse(txId) ?? 0},
                    ),
                  ),
                ],
                onSend: null, // handled inside _TxIdPicker
              ),
              const SizedBox(height: 20),

              // ── Availability ────────────────────────────────────────
              _SectionLabel('Availability'),
              Row(children: [
                Expanded(
                  child: _ActionButton(
                    label: 'Set Operative',
                    icon: Icons.check_circle_outline,
                    color: AppTheme.available,
                    enabled: isConnected,
                    onTap: () => _inject(context, 'ChangeAvailability', {
                      'connectorId': _selectedConnector,
                      'type': 'Operative',
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    label: 'Set Inoperative',
                    icon: Icons.block_outlined,
                    color: AppTheme.unavailable,
                    enabled: isConnected,
                    onTap: () => _inject(context, 'ChangeAvailability', {
                      'connectorId': _selectedConnector,
                      'type': 'Inoperative',
                    }),
                  ),
                ),
              ]),
              const SizedBox(height: 20),

              // ── Unlock Connector ────────────────────────────────────
              _SectionLabel('Connector'),
              _ActionButton(
                label: 'Unlock Connector ${_selectedConnector}',
                icon: Icons.lock_open_outlined,
                color: AppTheme.info,
                enabled: isConnected,
                onTap: () => _inject(context, 'UnlockConnector', {
                  'connectorId': _selectedConnector,
                }),
              ),
              const SizedBox(height: 20),

              // ── TriggerMessage ──────────────────────────────────────
              _SectionLabel('Trigger Message'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  'Heartbeat',
                  'StatusNotification',
                  'BootNotification',
                ].map((msg) => _SmallButton(
                      label: msg,
                      enabled: isConnected,
                      onTap: () => _inject(context, 'TriggerMessage', {
                        'requestedMessage': msg,
                        'connectorId': _selectedConnector,
                      }),
                    )).toList(),
              ),
              const SizedBox(height: 20),

              // ── Reset ───────────────────────────────────────────────
              _SectionLabel('System'),
              Row(children: [
                Expanded(
                  child: _ActionButton(
                    label: 'Soft Reset',
                    icon: Icons.refresh,
                    color: AppTheme.warning,
                    enabled: isConnected,
                    onTap: () => _inject(
                        context, 'Reset', {'type': 'Soft'}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    label: 'Hard Reset',
                    icon: Icons.restart_alt,
                    color: AppTheme.error,
                    enabled: isConnected,
                    onTap: () => _inject(
                        context, 'Reset', {'type': 'Hard'}),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              _ActionButton(
                label: 'Clear Cache',
                icon: Icons.cleaning_services_outlined,
                color: AppTheme.textSecondary,
                enabled: isConnected,
                onTap: () =>
                    _inject(context, 'ClearCache', {}),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

// ─── Widgets ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.info.withValues(alpha: 0.25)),
      ),
      child: const Row(
        children: [
          Icon(Icons.computer, color: AppTheme.info, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'CSMS Remote Control — Simulate commands that the Central System would send to the Charge Point.',
              style: TextStyle(color: AppTheme.info, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotConnectedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.wifi_off, color: AppTheme.warning, size: 16),
          SizedBox(width: 8),
          Text('Connect to CSMS first on the Dashboard tab.',
              style: TextStyle(color: AppTheme.warning, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  final String message;
  const _ResultBanner(this.message);

  @override
  Widget build(BuildContext context) {
    final isOk = message.startsWith('✓');
    final color = isOk ? AppTheme.available : AppTheme.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(message,
          style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _TagField extends StatelessWidget {
  final TextEditingController controller;
  const _TagField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      decoration: const InputDecoration(
        labelText: 'ID Tag',
        prefixIcon:
            Icon(Icons.nfc, color: AppTheme.textSecondary, size: 16),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}

class _TxIdPicker extends StatelessWidget {
  final List<dynamic> connectors;
  final void Function(String txId, int connectorId) onSelect;

  const _TxIdPicker(
      {required this.connectors, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final active = connectors
        .where((c) => c.activeTransactionId != null)
        .toList();

    if (active.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text('No active transactions',
            style:
                TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      );
    }

    return Column(
      children: active.map<Widget>((c) {
        return GestureDetector(
          onTap: () => onSelect(c.activeTransactionId!, c.id),
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppTheme.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.stop_circle,
                    color: AppTheme.error, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Stop TX #${c.activeTransactionId} (Connector ${c.id})',
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 12),
                  ),
                ),
                const Icon(Icons.send,
                    color: AppTheme.error, size: 14),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _CommandCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final bool enabled;
  final List<Widget> children;
  final VoidCallback? onSend;

  const _CommandCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.enabled,
    required this.children,
    required this.onSend,
  });

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
          Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    fontFamily: 'monospace')),
          ]),
          const SizedBox(height: 4),
          Text(description,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 11)),
          const SizedBox(height: 12),
          ...children,
          if (onSend != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: enabled ? onSend : null,
                icon: Icon(icon, size: 16),
                label: const Text('Send Command'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: AppTheme.surface,
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: enabled
              ? color.withValues(alpha: 0.1)
              : AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled
                ? color.withValues(alpha: 0.3)
                : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: enabled ? color : AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: enabled ? color : AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  const _SmallButton(
      {required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: enabled
              ? AppTheme.info.withValues(alpha: 0.1)
              : AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled
                ? AppTheme.info.withValues(alpha: 0.3)
                : AppTheme.border,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                color: enabled ? AppTheme.info : AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace')),
      ),
    );
  }
}
