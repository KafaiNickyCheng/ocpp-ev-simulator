// lib/screens/activity_log_screen.dart
// Live feed of all OCPP events received by the CSMS.
// Shows boots, heartbeats, authorizations, session starts/stops, commands sent.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/csms_provider.dart';
import '../utils/app_theme.dart';
import '../widgets/shared_widgets.dart';

class ActivityLogScreen extends StatelessWidget {
  const ActivityLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CsmsProvider>(
      builder: (context, provider, _) {
        final log = provider.activityLog;

        return Column(
          children: [
            // Header bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SectionHeader(
                title: 'LIVE ACTIVITY',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7, height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: provider.isConnected ? AppTheme.available : AppTheme.textSecondary,
                        boxShadow: provider.isConnected
                            ? [BoxShadow(color: AppTheme.available.withValues(alpha: 0.5), blurRadius: 4, spreadRadius: 1)]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      provider.isConnected ? 'Live' : 'Offline',
                      style: TextStyle(
                        color: provider.isConnected ? AppTheme.available : AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Log list
            Expanded(
              child: log.isEmpty
                  ? const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No activity yet',
                      subtitle: 'Events appear here as charge points connect and charge',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: log.length,
                      itemBuilder: (ctx, i) => _LogEntry(entry: log[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _LogEntry extends StatelessWidget {
  final ActivityLogEntry entry;
  const _LogEntry({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(entry.type);
    final icon  = _typeIcon(entry.type);
    final time  = DateFormat('HH:mm:ss').format(entry.timestamp.toLocal());

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline line + dot
          Column(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, color: color, size: 14),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Text(
                        entry.cpId,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      time,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  entry.message,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                ),
                if (entry.txId != null)
                  Text(
                    'TX #${entry.txId}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                const SizedBox(height: 6),
                Container(height: 1, color: AppTheme.border.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _typeColor(LogType type) {
    switch (type) {
      case LogType.boot:             return AppTheme.info;
      case LogType.offline:          return AppTheme.unavailable;
      case LogType.authorize:        return AppTheme.primary;
      case LogType.transactionStart: return AppTheme.charging;
      case LogType.transactionStop:  return AppTheme.available;
      case LogType.command:          return AppTheme.warning;
      case LogType.error:            return AppTheme.error;
    }
  }

  IconData _typeIcon(LogType type) {
    switch (type) {
      case LogType.boot:             return Icons.power_settings_new;
      case LogType.offline:          return Icons.cloud_off_outlined;
      case LogType.authorize:        return Icons.nfc;
      case LogType.transactionStart: return Icons.bolt;
      case LogType.transactionStop:  return Icons.check_circle_outline;
      case LogType.command:          return Icons.settings_remote;
      case LogType.error:            return Icons.error_outline;
    }
  }
}
