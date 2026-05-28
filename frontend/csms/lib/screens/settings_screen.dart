// lib/screens/settings_screen.dart
// Server URL configuration, connection management, and app info.

import 'package:csms_app/services/csms_signalr_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/csms_provider.dart';
import '../services/api_service.dart';
import '../utils/app_theme.dart';
import '../widgets/shared_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlCtrl;
  bool _testing = false;
  String? _testResult;
  bool? _testOk;

  @override
  void initState() {
    super.initState();
    final provider = context.read<CsmsProvider>();
    _urlCtrl = TextEditingController(text: provider.serverUrl);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CsmsProvider>(
      builder: (context, provider, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Connection ────────────────────────────────────────────────────
            const SectionHeader(title: 'BACKEND CONNECTION'),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status row
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
                          onPressed: provider.connectionState == CsmsConnectionState.connecting
                              ? null
                              : provider.connect,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: provider.connectionState == CsmsConnectionState.connecting
                              ? const SizedBox(
                                  width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.surface),
                                )
                              : const Text('Connect', style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),

                  if (provider.lastError != null) ...[
                    const SizedBox(height: 8),
                    Text(provider.lastError!, style: const TextStyle(color: AppTheme.error, fontSize: 12)),
                  ],

                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),

                  // URL field
                  TextField(
                    controller: _urlCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Backend URL',
                      hintText: 'http://192.168.1.x:5000',
                      prefixIcon: Icon(Icons.link, color: AppTheme.textSecondary, size: 18),
                    ),
                    onChanged: (_) => setState(() { _testResult = null; _testOk = null; }),
                  ),
                  const SizedBox(height: 10),

                  // Test + Save buttons
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _testing ? null : _testConnection,
                        icon: _testing
                            ? const SizedBox(width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
                            : const Icon(Icons.wifi_find, size: 16),
                        label: const Text('Test'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _saveUrl(provider),
                          icon: const Icon(Icons.save_outlined, size: 16),
                          label: const Text('Save & Reconnect'),
                        ),
                      ),
                    ],
                  ),

                  // Test result
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
                        Text(
                          _testResult!,
                          style: TextStyle(
                            color: _testOk == true ? AppTheme.available : AppTheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Connection tips ───────────────────────────────────────────────
            const SectionHeader(title: 'QUICK REFERENCE'),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TipRow(
                    label: 'SignalR Hub',
                    value: '${provider.serverUrl}/ocpp?clientType=csms',
                  ),
                  const SizedBox(height: 8),
                  _TipRow(
                    label: 'REST API',
                    value: '${provider.serverUrl}/api',
                  ),
                  const SizedBox(height: 8),
                  _TipRow(
                    label: 'Swagger UI',
                    value: '${provider.serverUrl}/swagger',
                  ),
                  const SizedBox(height: 8),
                  _TipRow(
                    label: 'CP connects via',
                    value: '?clientType=cp&cpId=CP-001',
                  ),
                  const SizedBox(height: 8),
                  _TipRow(
                    label: 'Client connects via',
                    value: '?clientType=client&idTag=TAG-001',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── About ─────────────────────────────────────────────────────────
            const SectionHeader(title: 'ABOUT'),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  _InfoRow('App', 'OCPP 1.6 CSMS'),
                  const Divider(height: 16),
                  _InfoRow('Protocol', 'OCPP 1.6 JSON'),
                  const Divider(height: 16),
                  _InfoRow('Transport', 'SignalR / WebSocket'),
                  const Divider(height: 16),
                  _InfoRow('Role', 'Central System (CSMS)'),
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  Future<void> _testConnection() async {
    setState(() { _testing = true; _testResult = null; _testOk = null; });
    final api    = ApiService();
    final ok     = await api.healthCheck(_urlCtrl.text.trim());
    setState(() {
      _testing    = false;
      _testOk     = ok;
      _testResult = ok ? 'Backend reachable ✓' : 'Cannot reach backend — check URL and network';
    });
  }

  Future<void> _saveUrl(CsmsProvider provider) async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    await provider.saveServerUrl(url);
    if (provider.isConnected) await provider.disconnect();
    await provider.connect();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved — reconnecting...'),
          backgroundColor: AppTheme.primary,
        ),
      );
    }
  }

  String _stateLabel(CsmsConnectionState s) {
    switch (s) {
      case CsmsConnectionState.connected:    return 'Connected';
      case CsmsConnectionState.connecting:   return 'Connecting...';
      case CsmsConnectionState.reconnecting: return 'Reconnecting...';
      case CsmsConnectionState.disconnected: return 'Disconnected';
    }
  }
}

class _TipRow extends StatelessWidget {
  final String label;
  final String value;
  const _TipRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: const TextStyle(
            color: AppTheme.info,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const Spacer(),
        Text(value, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
      ],
    );
  }
}
