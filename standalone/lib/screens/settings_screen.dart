// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ocpp_models.dart';
import '../providers/charge_point_provider.dart';
import '../utils/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _cpIdCtrl;
  late TextEditingController _urlCtrl;
  late TextEditingController _vendorCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _serialCtrl;
  late TextEditingController _fwCtrl;
  late TextEditingController _heartbeatCtrl;
  late TextEditingController _meterIntervalCtrl;
  late TextEditingController _maxPowerCtrl;
  late int _numConnectors;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<ChargePointProvider>().config;
    _cpIdCtrl = TextEditingController(text: cfg.chargePointId);
    _urlCtrl = TextEditingController(text: cfg.centralSystemUrl);
    _vendorCtrl = TextEditingController(text: cfg.vendor);
    _modelCtrl = TextEditingController(text: cfg.model);
    _serialCtrl = TextEditingController(text: cfg.serialNumber);
    _fwCtrl = TextEditingController(text: cfg.firmwareVersion);
    _heartbeatCtrl =
        TextEditingController(text: cfg.heartbeatInterval.toString());
    _meterIntervalCtrl =
        TextEditingController(text: cfg.meterValueInterval.toString());
    _maxPowerCtrl =
        TextEditingController(text: cfg.maxPowerKw.toStringAsFixed(1));
    _numConnectors = cfg.numberOfConnectors;
  }

  @override
  void dispose() {
    for (final c in [
      _cpIdCtrl, _urlCtrl, _vendorCtrl, _modelCtrl,
      _serialCtrl, _fwCtrl, _heartbeatCtrl, _meterIntervalCtrl, _maxPowerCtrl
    ]) c.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final newCfg = ChargePointConfig(
      chargePointId: _cpIdCtrl.text.trim(),
      centralSystemUrl: _urlCtrl.text.trim(),
      vendor: _vendorCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      serialNumber: _serialCtrl.text.trim(),
      firmwareVersion: _fwCtrl.text.trim(),
      heartbeatInterval:
          int.tryParse(_heartbeatCtrl.text.trim()) ?? 30,
      meterValueInterval:
          int.tryParse(_meterIntervalCtrl.text.trim()) ?? 15,
      maxPowerKw: double.tryParse(_maxPowerCtrl.text.trim()) ?? 22.0,
      numberOfConnectors: _numConnectors,
    );
    context.read<ChargePointProvider>().updateConfig(newCfg);
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configuration saved'),
        backgroundColor: AppTheme.available,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _markDirty() => setState(() => _dirty = true);

  @override
  Widget build(BuildContext context) {
    final isConnected = context.watch<ChargePointProvider>().connectionState ==
        CpConnectionState.connected;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        onChanged: _markDirty,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isConnected)
              _Warning(
                  'Disconnect from CSMS before changing configuration.'),
            _SectionHeader('Charge Point Identity'),
            _Field(
              controller: _cpIdCtrl,
              label: 'Charge Point ID',
              hint: 'CP-SIMULATOR-001',
              icon: Icons.ev_station,
              enabled: !isConnected,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            _Field(
              controller: _urlCtrl,
              label: 'Central System URL',
              hint: 'ws://localhost:9000/ocpp',
              icon: Icons.cloud_outlined,
              enabled: !isConnected,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 20),
            _SectionHeader('Hardware Info'),
            Row(children: [
              Expanded(
                child: _Field(
                  controller: _vendorCtrl,
                  label: 'Vendor',
                  hint: 'SimCo',
                  icon: Icons.business,
                  enabled: !isConnected,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Field(
                  controller: _modelCtrl,
                  label: 'Model',
                  hint: 'SimCharger X1',
                  icon: Icons.device_hub,
                  enabled: !isConnected,
                ),
              ),
            ]),
            Row(children: [
              Expanded(
                child: _Field(
                  controller: _serialCtrl,
                  label: 'Serial Number',
                  hint: 'SIM-2024-00001',
                  icon: Icons.numbers,
                  enabled: !isConnected,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Field(
                  controller: _fwCtrl,
                  label: 'Firmware Version',
                  hint: '1.0.0',
                  icon: Icons.memory,
                  enabled: !isConnected,
                ),
              ),
            ]),
            const SizedBox(height: 20),
            _SectionHeader('Charging Parameters'),
            Row(children: [
              Expanded(
                child: _Field(
                  controller: _maxPowerCtrl,
                  label: 'Max Power (kW)',
                  hint: '22.0',
                  icon: Icons.bolt,
                  keyboardType: TextInputType.number,
                  enabled: !isConnected,
                  validator: (v) {
                    final d = double.tryParse(v ?? '');
                    if (d == null || d <= 0) return 'Invalid';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumConnectorsPicker(
                  value: _numConnectors,
                  enabled: !isConnected,
                  onChanged: (v) => setState(() {
                    _numConnectors = v;
                    _markDirty();
                  }),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            _SectionHeader('Timing'),
            Row(children: [
              Expanded(
                child: _Field(
                  controller: _heartbeatCtrl,
                  label: 'Heartbeat Interval (s)',
                  hint: '30',
                  icon: Icons.favorite_border,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final i = int.tryParse(v ?? '');
                    if (i == null || i < 5) return '≥ 5s';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Field(
                  controller: _meterIntervalCtrl,
                  label: 'Meter Value Interval (s)',
                  hint: '15',
                  icon: Icons.electric_meter,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final i = int.tryParse(v ?? '');
                    if (i == null || i < 5) return '≥ 5s';
                    return null;
                  },
                ),
              ),
            ]),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _dirty && !isConnected ? _save : null,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save Configuration'),
              ),
            ),
            const SizedBox(height: 12),
            _AllowedTagsCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: AppTheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final bool enabled;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.enabled = true,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        validator: validator,
        style: TextStyle(
          color: enabled ? AppTheme.textPrimary : AppTheme.textSecondary,
          fontSize: 13,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: icon != null
              ? Icon(icon, size: 16, color: AppTheme.textSecondary)
              : null,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }
}

class _NumConnectorsPicker extends StatelessWidget {
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;
  const _NumConnectorsPicker(
      {required this.value,
      required this.enabled,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Connectors',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: enabled && value > 1 ? () => onChanged(value - 1) : null,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: const Icon(Icons.remove,
                      size: 16, color: AppTheme.textPrimary),
                ),
              ),
              Text('$value',
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              GestureDetector(
                onTap: enabled && value < 8 ? () => onChanged(value + 1) : null,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: const Icon(Icons.add,
                      size: 16, color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  final String message;
  const _Warning(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppTheme.warning, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    color: AppTheme.warning, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _AllowedTagsCard extends StatelessWidget {
  const _AllowedTagsCard();

  @override
  Widget build(BuildContext context) {
    const tags = [
      'TAG-001', 'TAG-002', 'TAG-003',
      'RFID-ADMIN', 'RFID-USER1', 'RFID-USER2', 'REMOTE-TAG',
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.credit_card, size: 16, color: AppTheme.primary),
              SizedBox(width: 8),
              Text('Mock Authorized ID Tags',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'These tags will be accepted by the mock CSMS',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tags
                .map((t) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Text(t,
                          style: const TextStyle(
                              color: AppTheme.primary,
                              fontSize: 11,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600)),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}
