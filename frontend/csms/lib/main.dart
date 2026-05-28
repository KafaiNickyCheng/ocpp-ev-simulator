// lib/main.dart
// Entry point for the CSMS Operator App.
// Sets up the provider, loads settings, connects to backend,
// and renders the main bottom-nav shell.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/csms_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/transactions_screen.dart';
import 'screens/tags_screen.dart';
import 'screens/activity_log_screen.dart';
import 'screens/settings_screen.dart';
import 'services/csms_signalr_service.dart';
import 'utils/app_theme.dart';
import 'widgets/shared_widgets.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => CsmsProvider(),
      child: const CsmsApp(),
    ),
  );
}

class CsmsApp extends StatelessWidget {
  const CsmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OCPP CSMS',
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

  final _screens = const [
    DashboardScreen(),
    TransactionsScreen(),
    TagsScreen(),
    ActivityLogScreen(),
    SettingsScreen(),
  ];

  final _labels = const [
    'Dashboard',
    'Sessions',
    'Tags',
    'Log',
    'Settings',
  ];

  final _icons = const [
    Icons.dashboard_outlined,
    Icons.receipt_long_outlined,
    Icons.nfc,
    Icons.timeline_outlined,
    Icons.settings_outlined,
  ];

  final _activeIcons = const [
    Icons.dashboard,
    Icons.receipt_long,
    Icons.nfc,
    Icons.timeline,
    Icons.settings,
  ];

  @override
  void initState() {
    super.initState();
    // Load saved settings and auto-connect on startup
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<CsmsProvider>();
      await provider.loadSettings();
      await provider.connect();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CsmsProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: AppTheme.surface,
          appBar: _buildAppBar(provider),
          body: Column(
            children: [
              // Connection status banner shown when not connected
              if (!provider.isConnected)
                ConnectionBanner(
                  message: _bannerMessage(provider.connectionState),
                  color: provider.connectionState == CsmsConnectionState.reconnecting
                      ? AppTheme.warning
                      : AppTheme.error,
                ),
              Expanded(child: _screens[_currentIndex]),
            ],
          ),
          bottomNavigationBar: _buildBottomNav(),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(CsmsProvider provider) {
    return AppBar(
      title: Row(
        children: [
          // App logo/icon
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
              const Text(
                'OCPP CSMS',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              Text(
                _labels[_currentIndex],
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ],
      ),
      actions: [
        // Live stats summary in the app bar
        if (provider.isConnected) ...[
          _AppBarStat(
            value: '${provider.stats.onlineChargePoints}',
            label: 'CPs',
            color: AppTheme.available,
          ),
          _AppBarStat(
            value: '${provider.stats.activeSessions}',
            label: 'Active',
            color: AppTheme.charging,
          ),
          if (provider.stats.faultedConnectors > 0)
            _AppBarStat(
              value: '${provider.stats.faultedConnectors}',
              label: 'Fault',
              color: AppTheme.error,
            ),
        ],
        // Connection indicator dot
        Padding(
          padding: const EdgeInsets.only(right: 16, left: 4),
          child: OnlineDot(isOnline: provider.isConnected),
        ),
      ],
    );
  }

  Widget _buildBottomNav() {
    return Consumer<CsmsProvider>(
      builder: (_, provider, __) {
        return BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          items: List.generate(_labels.length, (i) {
            // Show badge on log tab when there are active sessions
            final showBadge = i == 3 && provider.activityLog.isNotEmpty;
            return BottomNavigationBarItem(
              icon: showBadge
                  ? Badge(
                      backgroundColor: AppTheme.charging,
                      label: Text(
                        '${provider.activityLog.length > 99 ? '99+' : provider.activityLog.length}',
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

  String _bannerMessage(CsmsConnectionState state) {
    switch (state) {
      case CsmsConnectionState.reconnecting:
        return 'Reconnecting to backend...';
      case CsmsConnectionState.connecting:
        return 'Connecting to backend...';
      default:
        return 'Not connected — go to Settings to configure the backend URL';
    }
  }
}

class _AppBarStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _AppBarStat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 9)),
        ],
      ),
    );
  }
}
