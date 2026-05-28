// lib/services/ocpp_service.dart
// Fully local mock — no real WebSocket server required.
// Simulates a CSMS (Central System) that responds to every OCPP 1.6 message.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:uuid/uuid.dart';
import '../models/ocpp_models.dart';

typedef MessageHandler = void Function(
    String action, Map<String, dynamic> payload, String messageId);
typedef LogCallback = void Function(LogEntry entry);
typedef VoidCallback = void Function();

class OcppService {
  final _uuid = const Uuid();
  final _random = Random();

  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};
  final Map<String, MessageHandler> _remoteCommandHandlers = {};

  // Simulated heartbeat interval returned by mock CSMS
  int _heartbeatInterval = 30;
  bool _connected = false;
  Timer? _remoteCommandTimer;

  LogCallback? onLog;
  VoidCallback? onConnected;
  VoidCallback? onDisconnected;

  // Allowed RFID tags (mock whitelist)
  final Set<String> _allowedTags = {
    'TAG-001', 'TAG-002', 'TAG-003',
    'RFID-ADMIN', 'RFID-USER1', 'RFID-USER2',
    'REMOTE-TAG',
  };

  bool get isConnected => _connected;

  // ─── Connection ─────────────────────────────────────────────────────────────

  Future<void> connect(ChargePointConfig config) async {
    _log(LogDirection.system,
        'Connecting to mock CSMS (${config.centralSystemUrl})…');

    // Simulate network handshake delay
    await Future.delayed(Duration(milliseconds: 600 + _random.nextInt(400)));

    _connected = true;
    _log(LogDirection.system,
        'Mock CSMS connected ✓  [OCPP ${config.ocppVersion == OcppVersion.ocpp16 ? "1.6" : "2.0.1"} / JSON over WS]');
    onConnected?.call();
  }

  void disconnect() {
    _remoteCommandTimer?.cancel();
    _connected = false;
    _pendingRequests.forEach((_, c) {
      if (!c.isCompleted) c.completeError(Exception('Disconnected'));
    });
    _pendingRequests.clear();
    onDisconnected?.call();
    _log(LogDirection.system, 'Disconnected from Central System');
  }

  // ─── Send CALL (CP → CSMS) ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> sendCall(
      String action, Map<String, dynamic> payload) async {
    if (!_connected) throw Exception('Not connected');

    final msgId = _uuid.v4();
    final callFrame = [2, msgId, action, payload];
    final raw = jsonEncode(callFrame);

    _log(LogDirection.sent, '[$action] $msgId', rawData: raw);

    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[msgId] = completer;

    // Simulate network round-trip then mock CSMS reply
    Future.delayed(_mockLatency(), () {
      if (!_connected) {
        if (!completer.isCompleted) {
          completer.completeError(Exception('Disconnected'));
        }
        _pendingRequests.remove(msgId);
        return;
      }
      final response = _mockCsmsResponse(action, payload);
      final resultFrame = [3, msgId, response];
      final resultRaw = jsonEncode(resultFrame);

      _log(LogDirection.received,
          '[CallResult → $action] $msgId', rawData: resultRaw);

      if (!completer.isCompleted) {
        completer.complete(response);
      }
      _pendingRequests.remove(msgId);
    });

    // 30-second timeout
    Future.delayed(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        _pendingRequests.remove(msgId);
        completer.completeError(
            TimeoutException('Request $action timed out after 30s'));
      }
    });

    return completer.future;
  }

  // ─── Send CallResult (CP → CSMS, reply to remote command) ───────────────────

  void sendCallResult(String messageId, Map<String, dynamic> payload) {
    if (!_connected) return;
    final frame = [3, messageId, payload];
    final raw = jsonEncode(frame);
    _log(LogDirection.sent, '[CallResult] $messageId', rawData: raw);
  }

  // ─── Register Remote Command Handler ────────────────────────────────────────

  void registerCommandHandler(String action, MessageHandler handler) {
    _remoteCommandHandlers[action] = handler;
  }

  // ─── Simulate Remote Commands from CSMS → CP ────────────────────────────────
  // Call this to push a fake command from the CSMS side.

  void simulateRemoteCommand(String action, Map<String, dynamic> payload) {
    if (!_connected) return;
    final msgId = _uuid.v4();
    final frame = [2, msgId, action, payload];
    final raw = jsonEncode(frame);

    _log(LogDirection.received,
        '[Remote ← CSMS: $action] $msgId', rawData: raw);

    final handler = _remoteCommandHandlers[action];
    if (handler != null) {
      Future.delayed(_mockLatency(), () => handler(action, payload, msgId));
    } else {
      _log(LogDirection.system,
          'No handler for remote action: $action — sending NotImplemented');
      sendCallResult(msgId, {
        'status': 'NotImplemented',
        'errorDescription': 'Action $action not supported',
      });
    }
  }

  // ─── Mock CSMS Responses ─────────────────────────────────────────────────────

  Map<String, dynamic> _mockCsmsResponse(
      String action, Map<String, dynamic> payload) {
    switch (action) {
      case 'BootNotification':
        return {
          'status': 'Accepted',
          'currentTime': DateTime.now().toUtc().toIso8601String(),
          'interval': _heartbeatInterval,
        };

      case 'Heartbeat':
        return {
          'currentTime': DateTime.now().toUtc().toIso8601String(),
        };

      case 'Authorize':
        final idTag = payload['idTag'] as String? ?? '';
        final accepted = _allowedTags.contains(idTag);
        return {
          'idTagInfo': {
            'status': accepted ? 'Accepted' : 'Invalid',
            'expiryDate': DateTime.now()
                .add(const Duration(days: 365))
                .toUtc()
                .toIso8601String(),
          }
        };

      case 'StartTransaction':
        final idTag = payload['idTag'] as String? ?? '';
        final accepted = _allowedTags.contains(idTag);
        final txId = 1000 + _random.nextInt(9000);
        return {
          'transactionId': txId,
          'idTagInfo': {
            'status': accepted ? 'Accepted' : 'Invalid',
          },
        };

      case 'StopTransaction':
        return {
          'idTagInfo': {
            'status': 'Accepted',
          },
        };

      case 'MeterValues':
        return {}; // OCPP 1.6 MeterValues response is empty

      case 'StatusNotification':
        return {}; // Empty response per spec

      case 'DataTransfer':
        return {'status': 'Accepted'};

      case 'DiagnosticsStatusNotification':
        return {};

      case 'FirmwareStatusNotification':
        return {};

      default:
        _log(LogDirection.system, 'Unknown action: $action', isError: true);
        return {'status': 'Rejected'};
    }
  }

  Duration _mockLatency() =>
      Duration(milliseconds: 120 + _random.nextInt(180));

  // ─── Logging ─────────────────────────────────────────────────────────────────

  void _log(LogDirection dir, String msg,
      {String? rawData, bool isError = false}) {
    onLog?.call(LogEntry(
      timestamp: DateTime.now(),
      direction: dir,
      message: msg,
      rawData: rawData,
      isError: isError,
    ));
  }
}
