// lib/services/csms_signalr_service.dart
// Manages the SignalR connection between the CSMS app and the backend hub.
// Handles reconnection, event subscription, and all hub method calls.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:signalr_netcore/signalr_client.dart';

enum CsmsConnectionState { disconnected, connecting, connected, reconnecting }

class CsmsSignalRService {
  HubConnection? _connection;
  CsmsConnectionState _state = CsmsConnectionState.disconnected;

  // Notifiers so the provider can react to state changes
  final _stateController   = StreamController<CsmsConnectionState>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<CsmsConnectionState> get stateStream   => _stateController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  CsmsConnectionState get state => _state;

  // ─── Connect ──────────────────────────────────────────────────────────────

  Future<void> connect(String serverUrl) async {
    if (_state == CsmsConnectionState.connected ||
        _state == CsmsConnectionState.connecting) return;

    _setState(CsmsConnectionState.connecting);

    // Build connection URL — CSMS connects with ?clientType=csms
    final url = '${serverUrl.trimRight().replaceAll(RegExp(r'/$'), '')}/ocpp?clientType=csms';

    _connection = HubConnectionBuilder()
        .withUrl(url)
        .withAutomaticReconnect(
          retryDelays: [2000, 5000, 10000, 30000], // ms
        )
        .build();

    // ── Connection lifecycle callbacks ──────────────────────────────────────
    _connection!.onclose(({error}) {
      debugPrint('[CSMS] Connection closed: $error');
      _setState(CsmsConnectionState.disconnected);
    });

    _connection!.onreconnecting(({error}) {
      debugPrint('[CSMS] Reconnecting: $error');
      _setState(CsmsConnectionState.reconnecting);
    });

    _connection!.onreconnected(({connectionId}) {
      debugPrint('[CSMS] Reconnected: $connectionId');
      _setState(CsmsConnectionState.connected);
    });

    // ── Register all inbound event handlers ────────────────────────────────
    _registerEventHandlers();

    try {
      await _connection!.start();
      _setState(CsmsConnectionState.connected);
      debugPrint('[CSMS] Connected to $url');
    } catch (e) {
      debugPrint('[CSMS] Connection failed: $e');
      _setState(CsmsConnectionState.disconnected);
      rethrow;
    }
  }

  // ─── Disconnect ───────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    await _connection?.stop();
    _connection = null;
    _setState(CsmsConnectionState.disconnected);
  }

  // ─── Event Handlers (Backend → CSMS App) ─────────────────────────────────

  void _registerEventHandlers() {
    final c = _connection!;

    // CP came online after a boot/restart
    c.on('ChargePointBooted', (args) {
      _emit('ChargePointBooted', _arg(args));
    });

    // CP disconnected from the backend
    c.on('ChargePointOffline', (args) {
      _emit('ChargePointOffline', _arg(args));
    });

    // CP sent a Heartbeat — confirms it's still alive
    c.on('HeartbeatReceived', (args) {
      _emit('HeartbeatReceived', _arg(args));
    });

    // CP sent an Authorize request — tag + result
    c.on('AuthorizeRequest', (args) {
      _emit('AuthorizeRequest', _arg(args));
    });

    // A charging session started on a CP
    c.on('TransactionStarted', (args) {
      _emit('TransactionStarted', _arg(args));
    });

    // A charging session ended on a CP
    c.on('TransactionStopped', (args) {
      _emit('TransactionStopped', _arg(args));
    });

    // Live meter update during an active session
    c.on('MeterValuesUpdated', (args) {
      _emit('MeterValuesUpdated', _arg(args));
    });

    // Full connector status snapshot for a CP
    c.on('ChargePointStatusUpdate', (args) {
      _emit('ChargePointStatusUpdate', _arg(args));
    });
  }

  // ─── Remote Commands (CSMS App → Backend → CP) ───────────────────────────

  /// Tell a CP to start a session for an idTag on a connector
  Future<Map<String, dynamic>?> remoteStartTransaction(
      String cpId, String idTag, int? connectorId) async {
    return await _invoke('SendRemoteStartTransaction', [cpId, idTag, connectorId]);
  }

  /// Stop an active session by its transaction ID
  Future<Map<String, dynamic>?> remoteStopTransaction(
      String cpId, int transactionId) async {
    return await _invoke('SendRemoteStopTransaction', [cpId, transactionId]);
  }

  /// Change connector availability: "Operative" or "Inoperative"
  Future<Map<String, dynamic>?> changeAvailability(
      String cpId, int connectorId, String type) async {
    return await _invoke('SendChangeAvailability', [cpId, connectorId, type]);
  }

  /// Reset a CP: "Soft" (graceful) or "Hard" (immediate)
  Future<Map<String, dynamic>?> resetChargePoint(String cpId, String type) async {
    return await _invoke('SendReset', [cpId, type]);
  }

  /// Unlock a stuck connector cable
  Future<Map<String, dynamic>?> unlockConnector(String cpId, int connectorId) async {
    return await _invoke('SendUnlockConnector', [cpId, connectorId]);
  }

  /// Read configuration from a CP
  Future<Map<String, dynamic>?> getConfiguration(String cpId, List<String>? keys) async {
    return await _invoke('SendGetConfiguration', [cpId, keys]);
  }

  /// Write a configuration key on a CP
  Future<Map<String, dynamic>?> changeConfiguration(
      String cpId, String key, String value) async {
    return await _invoke('SendChangeConfiguration', [cpId, key, value]);
  }

  /// Trigger a specific message on a CP
  Future<Map<String, dynamic>?> triggerMessage(
      String cpId, String message, int? connectorId) async {
    return await _invoke('SendTriggerMessage', [cpId, message, connectorId]);
  }

  /// Clear the CP's local authorization cache
  Future<Map<String, dynamic>?> clearCache(String cpId) async {
    return await _invoke('SendClearCache', [cpId]);
  }

  // ─── Query Methods (fetches from backend DB via SignalR) ──────────────────

  Future<List<dynamic>?> getAllChargePoints() async {
    return await _invokeList('GetAllChargePoints', []);
  }

  Future<List<dynamic>?> getActiveTransactions() async {
    return await _invokeList('GetActiveTransactions', []);
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _invoke(String method, List<dynamic> args) async {
    if (_connection == null || _state != CsmsConnectionState.connected) {
      debugPrint('[CSMS] Cannot invoke $method — not connected');
      return null;
    }
    try {
      final result = await _connection!.invoke(method, args: List<Object>.from(args));
      return result as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[CSMS] Invoke $method failed: $e');
      return null;
    }
  }

  Future<List<dynamic>?> _invokeList(String method, List<dynamic> args) async {
    if (_connection == null || _state != CsmsConnectionState.connected) return null;
    try {
      final result = await _connection!.invoke(method, args: List<Object>.from(args));
      return result as List<dynamic>?;
    } catch (e) {
      debugPrint('[CSMS] Invoke $method failed: $e');
      return null;
    }
  }

  Map<String, dynamic> _arg(List<Object?>? args) {
    if (args == null || args.isEmpty) return {};
    final arg = args[0];
    if (arg is Map<String, dynamic>) return arg;
    if (arg is Map) return Map<String, dynamic>.from(arg);
    return {};
  }

  void _emit(String event, Map<String, dynamic> data) {
    _messageController.add({'event': event, ...data});
  }

  void _setState(CsmsConnectionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void dispose() {
    _stateController.close();
    _messageController.close();
    _connection?.stop();
  }
}