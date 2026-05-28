// lib/widgets/status_badge.dart

import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../models/ocpp_models.dart';

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool dot;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.dot = true,
  });

  factory StatusBadge.fromConnectionState(CpConnectionState state) {
    switch (state) {
      case CpConnectionState.connected:
        return StatusBadge(label: 'Connected', color: AppTheme.available);
      case CpConnectionState.connecting:
        return StatusBadge(label: 'Connecting', color: AppTheme.warning);
      case CpConnectionState.reconnecting:
        return StatusBadge(label: 'Reconnecting', color: AppTheme.warning);
      default:
        return StatusBadge(label: 'Offline', color: AppTheme.textSecondary);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
