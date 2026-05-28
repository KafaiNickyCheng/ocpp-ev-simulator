// lib/services/cp_signalr_service.dart
// Manages the SignalR connection between the ChargePoint simulator and the backend.
//
// Connection URL: ws://host/ocpp?clientType=cp&cpId=CP-SIM-001
//
// The CP uses a single hub method: OcppMessage(rawFrame) → returns CALLRESULT string
// The backend pushes remote commands via the "OcppCommand" event.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:signalr_netcore/signalr_client.dart';
import '../models/cp_models.dart';

class CpSignalRService {
  HubConnection? _connection;
  CpConnectionState _state = CpConnectionState.disconnected;

  final _stateController   = StreamController<CpConnectionState>.broadcast();
  final _commandController = StreamController<String>.broadcast();    // raw OCPP CALL frames from CSMS
  final _resultController  = StreamController<Map<String, dynamic>>.broadcast(); // ack results

  Stream<CpConnectionState>       get stateStream   => _stateController.stream;
  Stream<String>                  get commandStream  => _commandController.stream;

  CpConnectionState get state => _state;
  bool get isConnected => _state == CpConnectionState.connected;

  // ─── Connect ──────────────────────────────────────────────────────────────

  Future<void> connect(String serverUrl, String cpId) async {
    if (_state == CpConnectionState.connected ||
        _state == CpConnectionState.connecting) return;

    _setState(CpConnectionState.connecting);

    final base = serverUrl.trimRight().replaceAll(RegExp(r'/$'), '');
    final url  = '$base/ocpp?clientType=cp&cpId=${Uri.encodeComponent(cpId)}';

    _connection = HubConnectionBuilder()
        .withUrl(url)
        .withAutomaticReconnect(
          retryDelays: [2000, 5000, 10000, 30000],
        )
        .build();

    _connection!.onclose(({error}) {
      debugPrint('[CP] Connection closed: $error');
      _setState(CpConnectionState.disconnected);
    });

    _connection!.onreconnecting(({error}) {
      debugPrint('[CP] Reconnecting: $error');
      _setState(CpConnectionState.reconnecting);
    });

    _connection!.onreconnected(({connectionId}) {
      debugPrint('[CP] Reconnected: $connectionId');
      _setState(CpConnectionState.connected);
    });

    // ── Receive remote commands from CSMS ────────────────────────────────────
    // The backend calls Clients.Group("CP:{cpId}").SendAsync("OcppCommand", rawFrame)
    // rawFrame is a JSON string: [2, "msgId", "Action", { payload }]
    _connection!.on('OcppCommand', (args) {
      if (args != null && args.isNotEmpty) {
        final raw = args[0]?.toString() ?? '';
        debugPrint('[CP] ← OcppCommand: $raw');
        _commandController.add(raw);
      }
    });

    try {
      await _connection!.start();
      _setState(CpConnectionState.connected);
      debugPrint('[CP] Connected to $url');
    } catch (e) {
      debugPrint('[CP] Connection failed: $e');
      _setState(CpConnectionState.disconnected);
      rethrow;
    }
  }

  // ─── Disconnect ───────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    await _connection?.stop();
    _connection = null;
    _setState(CpConnectionState.disconnected);
  }

  // ─── Send OCPP Frame ──────────────────────────────────────────────────────
  // Invokes OcppMessage(rawFrame) on the hub and returns the CALLRESULT string.

  Future<String?> sendOcppMessage(String rawFrame) async {
    if (_connection == null || _state != CpConnectionState.connected) {
      debugPrint('[CP] Cannot send — not connected');
      return null;
    }
    try {
      debugPrint('[CP] → OcppMessage: $rawFrame');
      final result = await _connection!.invoke(
        'OcppMessage',
        args: [rawFrame],
      );
      debugPrint('[CP] ← Result: $result');
      return result?.toString();
    } catch (e) {
      debugPrint('[CP] sendOcppMessage failed: $e');
      return null;
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  void _setState(CpConnectionState s) {
    _state = s;
    _stateController.add(s);
  }

  void dispose() {
    _stateController.close();
    _commandController.close();
    _resultController.close();
    _connection?.stop();
  }
}
