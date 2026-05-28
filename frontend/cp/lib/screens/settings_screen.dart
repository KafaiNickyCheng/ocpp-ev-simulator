// lib/screens/settings_screen.dart
// Configure server URL, CP identity, connector count, simulation parameters.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cp_provider.dart';
import '../models/cp_models.dart';
import '../services/api_service.dart';
import '../utils/app_theme.dart';
import '../widgets/shared_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _serverUrlCtrl;
  late TextEditingController _cpIdCtrl;
  late TextEditingController _vendorCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _serialCtrl;
  late TextEditingController _fwCtrl;
  late TextEditingController _maxPowerCtrl;
  int _connectorCount      = 2;
  int _heartbeatInterval   = 30;
  int _meterValueInterval  = 15;

  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _serverUrlCtrl  = TextEditingController();
    _cpIdCtrl       = TextEditingController();
    _vendorCtrl     = TextEditingController();
    _modelCtrl      = TextEditingController();
    _serialCtrl     = TextEditingController();
    _fwCtrl         = TextEditingController();
    _maxPowerCtrl   = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFromProvider();
      // Re-load whenever provider notifies — catches backend sync completing
      context.read<CpProvider>().addListener(_onProviderChanged);
    });
  }

  

  void _loadFromProvider() {
    print("Load from provider get running");
    final s = context.read<CpProvider>().settings;
    _serverUrlCtrl.text  = s.serverUrl;
    _cpIdCtrl.text       = s.chargePointId;
    _vendorCtrl.text     = s.vendor;
    _modelCtrl.text      = s.model;
    _serialCtrl.text     = s.serialNumber;
    _fwCtrl.text         = s.firmwareVersion;
    _maxPowerCtrl.text   = s.simulatedMaxPowerKw.toString();
    print("the data is : ${s}");
    setState(() {
      _connectorCount     = s.connectorCount;
      _heartbeatInterval  = s.heartbeatIntervalSec;
      _meterValueInterval = s.meterValueIntervalSec;
      _dirty = false;
    });

    print("""
      serverUrl: ${s.serverUrl}
      chargePointId: ${s.chargePointId}
      vendor: ${s.vendor}
      model: ${s.model}
      serialNumber: ${s.serialNumber}
      firmwareVersion: ${s.firmwareVersion}
      simulatedMaxPowerKw: ${s.simulatedMaxPowerKw}
      connectorCount: ${s.connectorCount}
      heartbeatIntervalSec: ${s.heartbeatIntervalSec}
      meterValueIntervalSec: ${s.meterValueIntervalSec}
      dirty: $_dirty
      """);
  }

  void _onProviderChanged() {
    // Only reload if the user hasn't started editing (not dirty)
    // This prevents overwriting what the user is currently typing
    if (!_dirty && mounted) {
      _loadFromProvider();
    }
  }

  @override
  void dispose() {
    // Remove listener safely
    try {
      context.read<CpProvider>().removeListener(_onProviderChanged);
    } catch (_) {}
    for (final c in [_serverUrlCtrl, _cpIdCtrl, _vendorCtrl, _modelCtrl,
                    _serialCtrl, _fwCtrl, _maxPowerCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _markDirty() => setState(() => _dirty = true);

  @override
  Widget build(BuildContext context) {
    return Consumer<CpProvider>(
      builder: (ctx, provider, _) {
        return Form(
          key: _formKey,
          onChanged: _markDirty,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Connection ────────────────────────────────────────────────
              const SectionHeader(title: 'BACKEND CONNECTION'),
              const SizedBox(height: 10),
              _ConnectionCard(provider: provider),

              const SizedBox(height: 24),

              // ── Identity ──────────────────────────────────────────────────
              const SectionHeader(title: 'CHARGE POINT IDENTITY'),
              const SizedBox(height: 10),
              CardContainer(
                child: Column(
                  children: [
                    _SettingsField(
                      controller: _cpIdCtrl,
                      label: 'Charge Point ID',
                      hint: 'CP-SIM-001',
                      icon: Icons.ev_station_outlined,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _SettingsField(controller: _vendorCtrl, label: 'Vendor', hint: 'SimCo', icon: Icons.business_outlined)),
                        const SizedBox(width: 10),
                        Expanded(child: _SettingsField(controller: _modelCtrl, label: 'Model', hint: 'SimStation', icon: Icons.device_hub_outlined)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _SettingsField(controller: _serialCtrl, label: 'Serial Number', hint: 'SN-0001', icon: Icons.numbers_outlined)),
                        const SizedBox(width: 10),
                        Expanded(child: _SettingsField(controller: _fwCtrl, label: 'Firmware', hint: '1.0.0', icon: Icons.memory_outlined)),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Simulation ────────────────────────────────────────────────
              const SectionHeader(title: 'SIMULATION PARAMETERS'),
              const SizedBox(height: 10),
              CardContainer(
                child: Column(
                  children: [
                    // Connector count
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Connectors', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                              Text('Number of physical connectors', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                            ],
                          ),
                        ),
                        _StepperWidget(
                          value: _connectorCount,
                          min: 1, max: 4,
                          onChanged: (v) => setState(() { _connectorCount = v; _dirty = true; }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),

                    // Heartbeat interval
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Heartbeat Interval', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                              Text('Seconds between heartbeats', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                            ],
                          ),
                        ),
                        _StepperWidget(
                          value: _heartbeatInterval,
                          min: 10, max: 300, step: 10,
                          suffix: 's',
                          onChanged: (v) => setState(() { _heartbeatInterval = v; _dirty = true; }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),

                    // Meter value interval
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Meter Value Interval', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                              Text('Seconds between meter samples', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                            ],
                          ),
                        ),
                        _StepperWidget(
                          value: _meterValueInterval,
                          min: 5, max: 120, step: 5,
                          suffix: 's',
                          onChanged: (v) => setState(() { _meterValueInterval = v; _dirty = true; }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),

                    // Max power
                    _SettingsField(
                      controller: _maxPowerCtrl,
                      label: 'Max Simulated Power (kW)',
                      hint: '22.0',
                      icon: Icons.bolt_outlined,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Save Button ───────────────────────────────────────────────
              AnimatedOpacity(
                opacity: _dirty ? 1.0 : 0.5,
                duration: const Duration(milliseconds: 200),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _dirty ? () => _save(context, provider) : null,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save Settings'),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── About ─────────────────────────────────────────────────────
              const SectionHeader(title: 'ABOUT'),
              const SizedBox(height: 10),
              CardContainer(
                child: Column(
                  children: [
                    InfoRow('App',       'OCPP 1.6 ChargePoint Simulator'),
                    const Divider(height: 16),
                    InfoRow('Protocol',  'OCPP 1.6 JSON'),
                    const Divider(height: 16),
                    InfoRow('Transport', 'SignalR / WebSocket'),
                    const Divider(height: 16),
                    InfoRow('Role',      'Charge Point (CP)'),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Future<void> _save(BuildContext context, CpProvider provider) async {
    if (!_formKey.currentState!.validate()) return;

    final newSettings = provider.settings.copyWith(
      serverUrl:             _serverUrlCtrl.text.trim(),
      chargePointId:         _cpIdCtrl.text.trim(),
      vendor:                _vendorCtrl.text.trim(),
      model:                 _modelCtrl.text.trim(),
      serialNumber:          _serialCtrl.text.trim(),
      firmwareVersion:       _fwCtrl.text.trim(),
      connectorCount:        _connectorCount,
      heartbeatIntervalSec:  _heartbeatInterval,
      meterValueIntervalSec: _meterValueInterval,
      simulatedMaxPowerKw:   double.tryParse(_maxPowerCtrl.text) ?? 22.0,
    );

    await provider.saveSettings(newSettings);
    setState(() => _dirty = false);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved'),
          backgroundColor: AppTheme.primary,
        ),
      );
    }
  }
}

// ─── Connection Card ──────────────────────────────────────────────────────────

class _ConnectionCard extends StatefulWidget {
  final CpProvider provider;
  const _ConnectionCard({required this.provider});

  @override
  State<_ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends State<_ConnectionCard> {
  bool _testing = false;
  String? _testResult;
  bool? _testOk;

  Future<void> _testConnection() async {
    setState(() { _testing = true; _testResult = null; _testOk = null; });
    final ok = await ApiService().healthCheck(widget.provider.settings.serverUrl);
    setState(() {
      _testing = false;
      _testOk = ok;
      _testResult = ok ? 'Backend reachable ✓' : 'Cannot reach backend — check URL and network';
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    return CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OnlineDot(isOnline: provider.isConnected),
              const SizedBox(width: 8),
              Text(
                _stateLabel(provider.connectionState),
                style: TextStyle(
                  color: AppTheme.onlineColor(provider.isConnected),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (provider.isConnected)
                OutlinedButton(
                  onPressed: provider.disconnect,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: const BorderSide(color: AppTheme.error),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Disconnect', style: TextStyle(fontSize: 12)),
                )
              else
                ElevatedButton(
                  onPressed: provider.connectionState == CpConnectionState.connecting
                      ? null : provider.connect,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: provider.connectionState == CpConnectionState.connecting
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.surface))
                      : const Text('Connect', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          if (provider.lastError != null) ...[
            const SizedBox(height: 8),
            Text(provider.lastError!, style: const TextStyle(color: AppTheme.error, fontSize: 12)),
          ],
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
                    : const Icon(Icons.wifi_find, size: 16),
                label: const Text('Test Connection'),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _testOk == true ? Icons.check_circle_outline : Icons.error_outline,
                  color: _testOk == true ? AppTheme.available : AppTheme.error,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_testResult!,
                    style: TextStyle(color: _testOk == true ? AppTheme.available : AppTheme.error, fontSize: 12)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Backend URL', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              const SizedBox(height: 4),
              SelectableText(provider.settings.serverUrl,
                style: const TextStyle(color: AppTheme.info, fontSize: 12, fontFamily: 'monospace')),
              const SizedBox(height: 8),
              const Text('CP hub endpoint:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              const SizedBox(height: 4),
              SelectableText(
                '${provider.settings.serverUrl}/ocpp?clientType=cp&cpId=${provider.settings.chargePointId}',
                style: const TextStyle(color: AppTheme.info, fontSize: 11, fontFamily: 'monospace')),
            ],
          ),
        ],
      ),
    );
  }

  String _stateLabel(CpConnectionState s) {
    switch (s) {
      case CpConnectionState.connected:    return 'Connected';
      case CpConnectionState.connecting:   return 'Connecting...';
      case CpConnectionState.reconnecting: return 'Reconnecting...';
      case CpConnectionState.disconnected: return 'Disconnected';
    }
  }
}

// ─── Settings Text Field ──────────────────────────────────────────────────────

class _SettingsField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _SettingsField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppTheme.textSecondary, size: 18),
      ),
    );
  }
}

// ─── Stepper Widget ───────────────────────────────────────────────────────────

class _StepperWidget extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final int step;
  final String? suffix;
  final ValueChanged<int> onChanged;

  const _StepperWidget({
    required this.value,
    required this.min,
    required this.max,
    this.step = 1,
    this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepBtn(
          icon: Icons.remove,
          enabled: value > min,
          onTap: () => onChanged((value - step).clamp(min, max)),
        ),
        Container(
          width: 52,
          alignment: Alignment.center,
          child: Text(
            suffix != null ? '$value$suffix' : '$value',
            style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        _StepBtn(
          icon: Icons.add,
          enabled: value < max,
          onTap: () => onChanged((value + step).clamp(min, max)),
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.border),
        ),
        child: Icon(icon,
          size: 16,
          color: enabled ? AppTheme.textPrimary : AppTheme.textSecondary.withValues(alpha: 0.4)),
      ),
    );
  }
}
