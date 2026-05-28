// lib/screens/transactions_screen.dart
// Shows all transactions with filtering by CP, tag, status.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/csms_provider.dart';
import '../utils/app_theme.dart';
import '../widgets/shared_widgets.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  String? _statusFilter; // null=all, 'Active', 'Completed'
  List<Map<String, dynamic>> _txList = [];
  int _total = 0;
  int _page  = 1;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (reset) { _page = 1; _txList = []; }

    setState(() => _loading = true);
    final provider = context.read<CsmsProvider>();
    final result = await provider.getTransactionHistory(
      status: _statusFilter,
      page: _page,
    );
    final items = (result['items'] as List? ?? [])
        .cast<Map<String, dynamic>>();

    setState(() {
      _txList  = reset ? items : [..._txList, ...items];
      _total   = result['total'] ?? 0;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              _FilterChip(label: 'All',       value: null,         current: _statusFilter, onTap: _setFilter),
              const SizedBox(width: 8),
              _FilterChip(label: 'Active',    value: 'Active',     current: _statusFilter, onTap: _setFilter),
              const SizedBox(width: 8),
              _FilterChip(label: 'Completed', value: 'Completed',  current: _statusFilter, onTap: _setFilter),
              const Spacer(),
              Text('$_total total', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
            ],
          ),
        ),

        Expanded(
          child: _loading && _txList.isEmpty
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : _txList.isEmpty
                  ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'No transactions found')
                  : RefreshIndicator(
                      color: AppTheme.primary,
                      backgroundColor: AppTheme.surfaceCard,
                      onRefresh: () => _load(reset: true),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _txList.length + (_txList.length < _total ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          if (i == _txList.length) {
                            // Load more button
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: OutlinedButton(
                                  onPressed: () { _page++; _load(); },
                                  child: const Text('Load more'),
                                ),
                              ),
                            );
                          }
                          return _TransactionCard(tx: _txList[i]);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  void _setFilter(String? value) {
    setState(() => _statusFilter = value);
    _load(reset: true);
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String? value;
  final String? current;
  final void Function(String?) onTap;
  const _FilterChip({required this.label, required this.value, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withValues(alpha: 0.15) : AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppTheme.primary : AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ─── Transaction Card ─────────────────────────────────────────────────────────

class _TransactionCard extends StatelessWidget {
  final Map<String, dynamic> tx;
  const _TransactionCard({required this.tx});

  @override
  Widget build(BuildContext context) {
    final status   = tx['status'] as String? ?? 'Unknown';
    final isActive = status == 'Active';
    final color    = isActive ? AppTheme.charging : AppTheme.textSecondary;

    final startTime = DateTime.tryParse(tx['startTime'] ?? '');
    final stopTime  = tx['stopTime'] != null ? DateTime.tryParse(tx['stopTime'] ?? '') : null;
    final energy    = (tx['energyDeliveredKwh'] as num?)?.toDouble();

    final fmt = DateFormat('dd MMM HH:mm');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? AppTheme.charging.withValues(alpha: 0.3) : AppTheme.border,
        ),
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
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isActive ? Icons.bolt : Icons.check_circle_outline,
                  color: color, size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${tx['chargePointId']} · C${tx['connectorNumber']}',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600, fontSize: 13,
                      ),
                    ),
                    Text(
                      'Tag: ${tx['idTag']}  ·  TX #${tx['transactionId']}',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              StatusPill(label: status, color: color),
            ],
          ),
          const SizedBox(height: 10),
          // Detail row
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                MetricTile(
                  label: 'Start',
                  value: startTime != null ? fmt.format(startTime.toLocal()) : '—',
                  color: AppTheme.info,
                ),
                Container(width: 1, height: 28, color: AppTheme.border),
                MetricTile(
                  label: isActive ? 'Running' : 'End',
                  value: stopTime != null
                      ? fmt.format(stopTime.toLocal())
                      : isActive ? 'Active' : '—',
                  color: AppTheme.textSecondary,
                ),
                Container(width: 1, height: 28, color: AppTheme.border),
                MetricTile(
                  label: 'Energy',
                  value: energy != null ? '${energy.toStringAsFixed(3)} kWh' : '—',
                  color: AppTheme.charging,
                ),
              ],
            ),
          ),
          // Stop reason if available
          if (tx['stopReason'] != null && (tx['stopReason'] as String).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Reason: ${tx['stopReason']}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
