// lib/screens/tags_screen.dart
// RFID / ID Tag management — create, block, delete tags.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/csms_provider.dart';
import '../models/csms_models.dart';
import '../utils/app_theme.dart';
import '../widgets/shared_widgets.dart';

class TagsScreen extends StatefulWidget {
  const TagsScreen({super.key});

  @override
  State<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends State<TagsScreen> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    return Consumer<CsmsProvider>(
      builder: (context, provider, _) {
        final filtered = provider.tags
            .where((t) =>
                _filter.isEmpty ||
                t.tagId.toLowerCase().contains(_filter.toLowerCase()) ||
                (t.userName?.toLowerCase().contains(_filter.toLowerCase()) ?? false))
            .toList();

        return Column(
          children: [
            // Search bar + add button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _filter = v),
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Search tags...',
                        prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary, size: 18),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _showAddTagSheet(context, provider),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add'),
                  ),
                ],
              ),
            ),

            // Count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SectionHeader(
                title: 'ID TAGS',
                trailing: Text(
                  '${filtered.length} tags',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // List
            Expanded(
              child: filtered.isEmpty
                  ? const EmptyState(
                      icon: Icons.nfc,
                      title: 'No tags found',
                      subtitle: 'Add RFID or NFC tags to authorize charging sessions',
                    )
                  : RefreshIndicator(
                      color: AppTheme.primary,
                      backgroundColor: AppTheme.surfaceCard,
                      onRefresh: provider.refreshTags,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) => _TagCard(
                          tag: filtered[i],
                          provider: provider,
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  void _showAddTagSheet(BuildContext context, CsmsProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddTagSheet(provider: provider),
    );
  }
}

// ─── Tag Card ─────────────────────────────────────────────────────────────────

class _TagCard extends StatelessWidget {
  final IdTagModel tag;
  final CsmsProvider provider;
  const _TagCard({required this.tag, required this.provider});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(tag.status);
    final expStr = tag.expiryDate != null
        ? DateFormat('dd MMM yyyy').format(tag.expiryDate!.toLocal())
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          // NFC icon
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.nfc, color: statusColor, size: 22),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tag.tagId,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    fontFamily: 'monospace',
                  ),
                ),
                if (tag.userName != null)
                  Text(
                    tag.userName!,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                if (expStr != null)
                  Text(
                    'Expires $expStr',
                    style: TextStyle(
                      color: tag.isExpired ? AppTheme.error : AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          // Status + actions
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusPill(label: tag.status, color: statusColor),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tag.isBlocked)
                    _IconBtn(
                      icon: Icons.lock_open,
                      color: AppTheme.available,
                      tooltip: 'Accept',
                      onTap: () => provider.acceptTag(tag.tagId),
                    )
                  else
                    _IconBtn(
                      icon: Icons.block,
                      color: AppTheme.warning,
                      tooltip: 'Block',
                      onTap: () => provider.blockTag(tag.tagId),
                    ),
                  _IconBtn(
                    icon: Icons.delete_outline,
                    color: AppTheme.error,
                    tooltip: 'Delete',
                    onTap: () => _confirmDelete(context),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Accepted': return AppTheme.available;
      case 'Blocked':  return AppTheme.error;
      case 'Expired':  return AppTheme.warning;
      default:         return AppTheme.textSecondary;
    }
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        title: const Text('Delete Tag', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Delete tag "${tag.tagId}"? This cannot be undone.',
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
              provider.deleteTag(tag.tagId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.color, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }
}

// ─── Add Tag Sheet ────────────────────────────────────────────────────────────

class _AddTagSheet extends StatefulWidget {
  final CsmsProvider provider;
  const _AddTagSheet({required this.provider});

  @override
  State<_AddTagSheet> createState() => _AddTagSheetState();
}

class _AddTagSheetState extends State<_AddTagSheet> {
  final _tagCtrl  = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _tagCtrl.dispose();
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Register New Tag',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _tagCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Tag ID (RFID / NFC) *',
              prefixIcon: Icon(Icons.nfc, color: AppTheme.textSecondary, size: 18),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'User Name (optional)',
              prefixIcon: Icon(Icons.person_outline, color: AppTheme.textSecondary, size: 18),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _noteCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              prefixIcon: Icon(Icons.note_outlined, color: AppTheme.textSecondary, size: 18),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 12)),
          ],

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.surface),
                    )
                  : const Text('Register Tag'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_tagCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Tag ID is required');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final success = await widget.provider.createTag(
        _tagCtrl.text.trim(),
        _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      if (success && mounted) {
        Navigator.pop(context);
      } else if (mounted) {
        setState(() => _error = 'Failed — tag ID may already exist');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
