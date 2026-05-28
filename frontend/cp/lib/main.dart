// lib/main.dart
// Entry point for the OCPP 1.6 ChargePoint Simulator app.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/cp_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/ocpp_log_screen.dart';
import 'screens/settings_screen.dart';
import 'utils/app_theme.dart';
import 'widgets/shared_widgets.dart';
import 'models/cp_models.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => CpProvider(),
      child: const CpApp(),
    ),
  );
}

class CpApp extends StatelessWidget {
  const CpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OCPP ChargePoint',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const _AppShell(),
    );
  }
}

// ─── App Shell ────────────────────────────────────────────────────────────────

class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _currentIndex = 0;

  final _screens = [
    DashboardScreen(),
    OcppLogScreen(),
    SettingsScreen(),
  ];

  final _labels      = const ['Simulator', 'OCPP Log', 'Settings'];
  final _icons       = const [Icons.ev_station_outlined, Icons.chat_bubble_outline, Icons.settings_outlined];
  final _activeIcons = const [Icons.ev_station, Icons.chat_bubble, Icons.settings];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<CpProvider>();
      await provider.loadSettings();
      await provider.connect();
      // Only boot if connect actually succeeded
      await Future.delayed(const Duration(milliseconds: 300));
      if (provider.isConnected && !provider.isBooted) {
        await provider.boot();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CpProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: AppTheme.surface,
          appBar: _buildAppBar(provider),
          body: Column(
            children: [
              // Connection banner when not connected
              if (!provider.isConnected)
                ConnectionBanner(
                  message: provider.connectionState == CpConnectionState.reconnecting
                      ? 'Reconnecting to backend...'
                      : provider.connectionState == CpConnectionState.connecting
                          ? 'Connecting to backend...'
                          : 'Offline — go to Settings to configure the backend URL',
                  color: provider.connectionState == CpConnectionState.reconnecting
                      ? AppTheme.warning
                      : AppTheme.error,
                ),
              Expanded(child: _screens[_currentIndex]),
            ],
          ),
          bottomNavigationBar: _buildBottomNav(provider),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(CpProvider provider) {
    final chargingCount = provider.connectors.where((c) => c.isCharging).length;

    return AppBar(
      title: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(Icons.ev_station, color: AppTheme.primary, size: 16),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ChargePoint',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              Text(
                provider.settings.chargePointId,
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (provider.isConnected && provider.isBooted) ...[
          if (chargingCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$chargingCount',
                    style: const TextStyle(color: AppTheme.charging, fontSize: 14, fontWeight: FontWeight.bold)),
                  const Text('Charging',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 9)),
                ],
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.only(right: 16, left: 4),
          child: OnlineDot(isOnline: provider.isConnected),
        ),
      ],
    );
  }

  Widget _buildBottomNav(CpProvider provider) {
    return Consumer<CpProvider>(
      builder: (_, p, __) {
        final hasOcppActivity = p.ocppLog.isNotEmpty;
        return BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          items: List.generate(_labels.length, (i) {
            final showBadge = i == 1 && hasOcppActivity && _currentIndex != 1;
            return BottomNavigationBarItem(
              icon: showBadge
                  ? Badge(
                      backgroundColor: AppTheme.info,
                      label: Text(
                        '${p.ocppLog.length > 99 ? "99+" : p.ocppLog.length}',
                        style: const TextStyle(fontSize: 9),
                      ),
                      child: Icon(_icons[i]),
                    )
                  : Icon(_icons[i]),
              activeIcon: Icon(_activeIcons[i]),
              label: _labels[i],
            );
          }),
        );
      },
    );
  }
}
