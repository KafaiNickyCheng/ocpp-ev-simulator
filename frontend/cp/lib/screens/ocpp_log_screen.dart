// lib/screens/ocpp_log_screen.dart
// Real-time OCPP 1.6 message log — shows every frame sent and received.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/cp_provider.dart';
import '../models/cp_models.dart';
import '../utils/app_theme.dart';
import '../widgets/shared_widgets.dart';

class OcppLogScreen extends StatelessWidget {
  const OcppLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CpProvider>(
      builder: (context, provider, _) {
        final log = provider.ocppLog;

        return Column(
          children: [
            // Header bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: SectionHeader(
                title: 'OCPP MESSAGE LOG',
                trailing: StatusPill(
                  label: '${log.length} entries',
                  color: AppTheme.textSecondary,
                ),
              ),
            ),

            if (log.isEmpty)
              const Expanded(
                child: EmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: 'No messages yet',
                  subtitle: 'Connect and boot the charge point to see OCPP traffic',
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: log.length,
                  itemBuilder: (ctx, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _LogEntry(entry: log[i]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LogEntry extends StatelessWidget {
  final OcppLogEntry entry;
  const _LogEntry({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isSent     = entry.isSent;
    final isError    = entry.isError;
    final dirColor   = isError
        ? AppTheme.error
        : isSent ? AppTheme.info : AppTheme.available;
    final dirLabel   = isSent ? '↑ SENT' : '↓ RECV';
    final timeStr    = DateFormat('HH:mm:ss').format(entry.timestamp);

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: '[${entry.action}] ${entry.payload}'));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Copied to clipboard'), backgroundColor: AppTheme.primary),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isError ? AppTheme.error.withValues(alpha: 0.4) : AppTheme.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Direction indicator
            Container(
              width: 40,
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: dirColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(dirLabel,
                style: TextStyle(color: dirColor, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(entry.action,
                        style: TextStyle(
                          color: isError ? AppTheme.error : AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(timeStr,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                    ],
                  ),
                  if (entry.payload.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(entry.payload,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
