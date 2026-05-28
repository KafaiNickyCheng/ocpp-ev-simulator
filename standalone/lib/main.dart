// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/charge_point_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/log_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/remote_screen.dart';
import 'utils/app_theme.dart';

import 'models/ocpp_models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const OcppSimulatorApp());
}

class OcppSimulatorApp extends StatelessWidget {
  const OcppSimulatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ChargePointProvider(),
      child: MaterialApp(
        title: 'OCPP 1.6 Simulator',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const MainShell(),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  static const _titles = [
    'Charge Point',
    'CSMS Remote',
    'Message Log',
    'Settings',
  ];

  static const _screens = [
    DashboardScreen(),
    RemoteScreen(),
    LogScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.bolt, color: AppTheme.primary, size: 16),
            ),
            const SizedBox(width: 10),
            Text(_titles[_currentIndex]),
          ],
        ),
        actions: [
          _ConnectionDot(),
          const SizedBox(width: 12),
        ],
      ),
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.ev_station_outlined),
              activeIcon: Icon(Icons.ev_station),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.computer_outlined),
              activeIcon: Icon(Icons.computer),
              label: 'CSMS',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              activeIcon: Icon(Icons.receipt_long),
              label: 'Logs',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ChargePointProvider>(
      builder: (_, provider, __) {
        Color color;
        switch (provider.connectionState) {
          case CpConnectionState.connected:
            color = AppTheme.available;
            break;
          case CpConnectionState.connecting:
          case CpConnectionState.reconnecting:
            color = AppTheme.warning;
            break;
          default:
            color = AppTheme.textSecondary;
        }
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: provider.connectionState == CpConnectionState.connected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
        );
      },
    );
  }
}
