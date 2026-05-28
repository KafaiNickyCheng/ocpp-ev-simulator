// lib/screens/log_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../models/ocpp_models.dart';
import '../providers/charge_point_provider.dart';
import '../utils/app_theme.dart';

// ─── OCPP message groups ──────────────────────────────────────────────────────

class _MsgGroup {
  final String title;
  final String keyword;   // matched against LogEntry.message
  final IconData icon;
  final Color color;

  const _MsgGroup({
    required this.title,
    required this.keyword,
    required this.icon,
    required this.color,
  });
}

const _groups = [
  _MsgGroup(title: 'BootNotification',     keyword: 'BootNotification',     icon: Icons.power_settings_new,    color: AppTheme.primary),
  _MsgGroup(title: 'Heartbeat',            keyword: 'Heartbeat',            icon: Icons.favorite_border,       color: AppTheme.error),
  _MsgGroup(title: 'StatusNotification',   keyword: 'StatusNotification',   icon: Icons.info_outline,          color: AppTheme.info),
  _MsgGroup(title: 'Authorize',            keyword: 'Authorize',            icon: Icons.credit_card,           color: AppTheme.warning),
  _MsgGroup(title: 'StartTransaction',     keyword: 'StartTransaction',     icon: Icons.play_circle_outline,   color: AppTheme.available),
  _MsgGroup(title: 'StopTransaction',      keyword: 'StopTransaction',      icon: Icons.stop_circle_outlined,  color: AppTheme.error),
  _MsgGroup(title: 'MeterValues',          keyword: 'MeterValues',          icon: Icons.electric_meter,        color: AppTheme.charging),
  _MsgGroup(title: 'RemoteStart/Stop',     keyword: 'Remote',               icon: Icons.computer,              color: AppTheme.info),
  _MsgGroup(title: 'System / Other',       keyword: '',                     icon: Icons.settings_outlined,     color: AppTheme.textSecondary),
];

// ─── Screen ───────────────────────────────────────────────────────────────────

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

enum _ViewMode { grouped, timeline }

class _LogScreenState extends State<LogScreen> {
  final _scrollController = ScrollController();
  _ViewMode _viewMode = _ViewMode.grouped;
  LogDirection? _dirFilter;
  bool _autoScroll = true;

  // Which groups are collapsed
  final Set<String> _collapsed = {};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Assign a log entry to a group
  String _groupFor(LogEntry e) {
    for (final g in _groups) {
      if (g.keyword.isEmpty) continue;
      if (e.message.contains(g.keyword) ||
          (e.rawData?.contains(g.keyword) ?? false)) {
        return g.title;
      }
    }
    return 'System / Other';
  }

  List<LogEntry> _filtered(List<LogEntry> all) {
    if (_dirFilter == null) return all;
    return all.where((l) => l.direction == _dirFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChargePointProvider>(
      builder: (context, provider, _) {
        final logs = _filtered(provider.logs);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_autoScroll &&
              _viewMode == _ViewMode.timeline &&
              _scrollController.hasClients) {
            _scrollController
                .jumpTo(_scrollController.position.maxScrollExtent);
          }
        });

        return Column(
          children: [
            _buildToolbar(context, provider),
            Expanded(
              child: logs.isEmpty
                  ? _buildEmpty()
                  : _viewMode == _ViewMode.grouped
                      ? _buildGrouped(logs)
                      : _buildTimeline(logs),
            ),
          ],
        );
      },
    );
  }

  // ── Toolbar ────────────────────────────────────────────────────────────────

  Widget _buildToolbar(BuildContext context, ChargePointProvider provider) {
    return Container(
      color: AppTheme.surfaceElevated,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        children: [
          Row(
            children: [
              // View mode toggle
              _ToggleButton(
                icon: Icons.view_agenda_outlined,
                label: 'Grouped',
                active: _viewMode == _ViewMode.grouped,
                onTap: () => setState(() => _viewMode = _ViewMode.grouped),
              ),
              const SizedBox(width: 6),
              _ToggleButton(
                icon: Icons.format_list_bulleted,
                label: 'Timeline',
                active: _viewMode == _ViewMode.timeline,
                onTap: () => setState(() => _viewMode = _ViewMode.timeline),
              ),
              const Spacer(),
              // Auto-scroll (timeline only)
              if (_viewMode == _ViewMode.timeline)
                IconButton(
                  icon: Icon(
                    _autoScroll
                        ? Icons.vertical_align_bottom
                        : Icons.pause,
                    size: 18,
                    color: _autoScroll
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                  ),
                  tooltip: 'Auto-scroll',
                  onPressed: () =>
                      setState(() => _autoScroll = !_autoScroll),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                ),
              // Collapse all (grouped only)
              if (_viewMode == _ViewMode.grouped)
                IconButton(
                  icon: Icon(
                    _collapsed.length == _groups.length
                        ? Icons.unfold_more
                        : Icons.unfold_less,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                  tooltip: _collapsed.length == _groups.length
                      ? 'Expand all'
                      : 'Collapse all',
                  onPressed: _toggleCollapseAll,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: AppTheme.textSecondary),
                tooltip: 'Clear logs',
                onPressed: provider.clearLogs,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Direction filter row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _dirFilter == null,
                  onTap: () => setState(() => _dirFilter = null),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: '↑ Sent',
                  selected: _dirFilter == LogDirection.sent,
                  color: AppTheme.info,
                  onTap: () =>
                      setState(() => _dirFilter = LogDirection.sent),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: '↓ Received',
                  selected: _dirFilter == LogDirection.received,
                  color: AppTheme.charging,
                  onTap: () =>
                      setState(() => _dirFilter = LogDirection.received),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: '⚙ System',
                  selected: _dirFilter == LogDirection.system,
                  color: AppTheme.textSecondary,
                  onTap: () =>
                      setState(() => _dirFilter = LogDirection.system),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleCollapseAll() {
    setState(() {
      if (_collapsed.length == _groups.length) {
        _collapsed.clear();
      } else {
        _collapsed.addAll(_groups.map((g) => g.title));
      }
    });
  }

  // ── Grouped view ───────────────────────────────────────────────────────────

  Widget _buildGrouped(List<LogEntry> logs) {
    // bucket entries by group
    final Map<String, List<LogEntry>> buckets = {
      for (final g in _groups) g.title: [],
    };
    for (final e in logs) {
      buckets[_groupFor(e)]!.add(e);
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: _groups.map((g) {
        final entries = buckets[g.title]!;
        return _GroupSection(
          group: g,
          entries: entries,
          collapsed: _collapsed.contains(g.title),
          onToggle: () => setState(() {
            if (_collapsed.contains(g.title)) {
              _collapsed.remove(g.title);
            } else {
              _collapsed.add(g.title);
            }
          }),
        );
      }).toList(),
    );
  }

  // ── Timeline view (original flat list) ────────────────────────────────────

  Widget _buildTimeline(List<LogEntry> logs) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      itemCount: logs.length,
      itemBuilder: (_, i) => _LogTile(entry: logs[i]),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 48, color: AppTheme.textSecondary),
          SizedBox(height: 12),
          Text('No messages yet',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          SizedBox(height: 4),
          Text('Connect to the Central System to begin',
              style:
                  TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

// ─── Group Section ────────────────────────────────────────────────────────────

class _GroupSection extends StatelessWidget {
  final _MsgGroup group;
  final List<LogEntry> entries;
  final bool collapsed;
  final VoidCallback onToggle;

  const _GroupSection({
    required this.group,
    required this.entries,
    required this.collapsed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: entries.isEmpty
              ? AppTheme.border
              : group.color.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          // ── Header ──
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: group.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(group.icon,
                        color: group.color, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      group.title,
                      style: TextStyle(
                        color: entries.isEmpty
                            ? AppTheme.textSecondary
                            : AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  // Count badge
                  if (entries.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: group.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${entries.length}',
                        style: TextStyle(
                          color: group.color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    const Text('—',
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12)),
                  const SizedBox(width: 8),
                  Icon(
                    collapsed
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    size: 18,
                    color: entries.isEmpty
                        ? AppTheme.border
                        : AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          // ── Entries ──
          if (!collapsed && entries.isNotEmpty) ...[
            Divider(
                height: 1,
                color: group.color.withValues(alpha: 0.2)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Column(
                children: entries
                    .map((e) => _LogTile(entry: e, compact: true))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Log Tile ─────────────────────────────────────────────────────────────────

class _LogTile extends StatefulWidget {
  final LogEntry entry;
  final bool compact;
  const _LogTile({required this.entry, this.compact = false});

  @override
  State<_LogTile> createState() => _LogTileState();
}

class _LogTileState extends State<_LogTile> {
  bool _expanded = false;

  Color get _color {
    if (widget.entry.isError) return AppTheme.error;
    switch (widget.entry.direction) {
      case LogDirection.sent:
        return AppTheme.info;
      case LogDirection.received:
        return AppTheme.charging;
      case LogDirection.system:
        return AppTheme.textSecondary;
    }
  }

  String get _prefix {
    switch (widget.entry.direction) {
      case LogDirection.sent:
        return '↑ OUT';
      case LogDirection.received:
        return '↓ IN ';
      case LogDirection.system:
        return '⚙ SYS';
    }
  }

  String get _formattedTime {
    final t = widget.entry.timestamp;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.'
        '${(t.millisecond ~/ 10).toString().padLeft(2, '0')}';
  }

  String? get _prettyJson {
    final raw = widget.entry.rawData;
    if (raw == null) return null;
    try {
      final obj = jsonDecode(raw);
      return const JsonEncoder.withIndent('  ').convert(obj);
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: widget.entry.isError
              ? AppTheme.error.withValues(alpha: 0.08)
              : AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _expanded
                ? _color.withValues(alpha: 0.4)
                : AppTheme.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: widget.compact ? 6 : 8),
              child: Row(
                children: [
                  Text(_prefix,
                      style: TextStyle(
                          color: _color,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace')),
                  const SizedBox(width: 8),
                  Text(_formattedTime,
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10,
                          fontFamily: 'monospace')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.entry.message,
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.entry.rawData != null)
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                ],
              ),
            ),
            if (_expanded && _prettyJson != null) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SelectableText(
                        _prettyJson!,
                        style: const TextStyle(
                          color: AppTheme.charging,
                          fontSize: 11,
                          fontFamily: 'monospace',
                          height: 1.5,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy,
                          size: 14,
                          color: AppTheme.textSecondary),
                      onPressed: () => Clipboard.setData(
                          ClipboardData(text: _prettyJson!)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 24, minHeight: 24),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Small widgets ────────────────────────────────────────────────────────────

class _ToggleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ToggleButton(
      {required this.icon,
      required this.label,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.primary.withValues(alpha: 0.15)
              : AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active
                ? AppTheme.primary.withValues(alpha: 0.4)
                : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color:
                    active ? AppTheme.primary : AppTheme.textSecondary),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: active
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: active
                        ? FontWeight.w600
                        : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? c.withValues(alpha: 0.2)
              : AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? c.withValues(alpha: 0.5)
                : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? c : AppTheme.textSecondary,
            fontSize: 11,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.normal,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}