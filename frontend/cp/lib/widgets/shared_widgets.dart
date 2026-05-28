// lib/widgets/shared_widgets.dart
// Reusable UI components — mirrors the CSMS app's shared_widgets.dart.

import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

// ─── Status Pill ──────────────────────────────────────────────────────────────

class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final double fontSize;

  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ─── Online Dot ──────────────────────────────────────────────────────────────

class OnlineDot extends StatelessWidget {
  final bool isOnline;
  const OnlineDot({super.key, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isOnline ? AppTheme.available : AppTheme.unavailable,
        boxShadow: isOnline
            ? [BoxShadow(color: AppTheme.available.withValues(alpha: 0.5), blurRadius: 4, spreadRadius: 1)]
            : null,
      ),
    );
  }
}

// ─── Stat Card ────────────────────────────────────────────────────────────────

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value,
                  style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(label,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title,
          style: const TextStyle(
            color: AppTheme.textSecondary, fontSize: 11,
            fontWeight: FontWeight.w700, letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.textSecondary, size: 48),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Connection Banner ────────────────────────────────────────────────────────

class ConnectionBanner extends StatelessWidget {
  final String message;
  final Color color;
  const ConnectionBanner({super.key, required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.withValues(alpha: 0.15),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: color, fontSize: 12))),
        ],
      ),
    );
  }
}

// ─── Info Row ─────────────────────────────────────────────────────────────────

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const InfoRow(this.label, this.value, {super.key, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const Spacer(),
        Text(value, style: TextStyle(color: valueColor ?? AppTheme.textPrimary, fontSize: 13)),
      ],
    );
  }
}

// ─── Card Container ───────────────────────────────────────────────────────────

class CardContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? borderColor;

  const CardContainer({super.key, required this.child, this.padding, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor ?? AppTheme.border),
      ),
      child: child,
    );
  }
}
