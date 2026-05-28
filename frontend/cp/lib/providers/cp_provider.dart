// lib/providers/cp_provider.dart
// Central state and OCPP 1.6 logic for the ChargePoint simulator.
//
// Responsibilities:
//  - Owns the SignalR connection via CpSignalRService
//  - Maintains connector state machines (Available → Preparing → Charging → Finishing)
//  - Runs heartbeat timer (every N seconds)
//  - Runs meter value timer per active connector (every N seconds)
//  - Simulates realistic energy/power values during charging
//  - Handles incoming remote commands from CSMS (RemoteStart, RemoteStop, Reset, etc.)
//  - Persists settings via shared_preferences
//  - Maintains in-memory OCPP message log (last 100 frames)

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cp_models.dart';

import '../services/api_service.dart';
import '../services/cp_signalr_service.dart';
import '../services/ocpp_message_builder.dart';

class CpProvider extends ChangeNotifier {
  final CpSignalRService _hub = CpSignalRService();

  // ─── Settings ─────────────────────────────────────────────────────────────
  CpSettings _settings = const CpSettings();
  CpSettings get settings => _settings;

  // ─── Connection State ─────────────────────────────────────────────────────
  CpConnectionState _connectionState = CpConnectionState.disconnected;
  CpConnectionState get connectionState => _connectionState;
  bool get isConnected => _connectionState == CpConnectionState.connected;
  bool get isBooted => _isBooted;
  bool _isBooted = false;

  String? _lastError;
  String? get lastError => _lastError;

  // ─── Connector States ─────────────────────────────────────────────────────
  List<ConnectorState> _connectors = [];
  List<ConnectorState> get connectors => _connectors;

  ConnectorState? connector(int id) =>
      _connectors.where((c) => c.connectorId == id).firstOrNull;

  // ─── OCPP Message Log ─────────────────────────────────────────────────────
  final List<OcppLogEntry> _log = [];
  List<OcppLogEntry> get ocppLog => List.unmodifiable(_log);

  // ─── Timers ───────────────────────────────────────────────────────────────
  Timer? _heartbeatTimer;
  final Map<int, Timer> _meterTimers = {}; // connectorId → timer

  // ─── Subscriptions ────────────────────────────────────────────────────────
  StreamSubscription? _stateSub;
  StreamSubscription? _commandSub;

  // ─── RNG for realistic simulation ────────────────────────────────────────
  final _rng = Random();

  CpProvider() {
    _listenToHub();
  }

  // =========================================================================
  // SETTINGS
  // =========================================================================

  /// Loads ALL settings.
  ///
  /// Strategy:
  ///  1. Read simulator-only settings from SharedPreferences (serverUrl,
  ///     chargePointId, heartbeat/meter intervals, maxPower).
  ///  2. Attempt to fetch identity fields (vendor/model/serial/fw/connectors)
  ///     from the backend — it is the single source of truth.
  ///  3. If the backend is reachable and returns data → use it, persist it
  ///     locally so the next cold-start has a good fallback.
  ///  4. If the backend is not reachable or the CP isn't in the DB yet →
  ///     fall back to whatever was last saved in SharedPreferences.
  ///     Only use the compile-time defaults when SharedPreferences is also
  ///     empty (i.e. very first ever launch).
  Future<void> loadSettings() async {
    final p = await SharedPreferences.getInstance();

    // ── Step 1: simulator-only settings (never stored on backend) ──────────
    final serverUrl             = p.getString('cp_serverUrl')           ?? 'http://localhost:5000';
    final chargePointId         = p.getString('cp_chargePointId')       ?? 'CP-SIM-001';
    final heartbeatIntervalSec  = p.getInt('cp_heartbeatInterval')      ?? 30;
    final meterValueIntervalSec = p.getInt('cp_meterValueInterval')     ?? 15;
    final simulatedMaxPowerKw   = p.getDouble('cp_simulatedMaxPowerKw') ?? 22.0;

    // ── Step 2: identity fields — prefer SharedPreferences over compile-time
    //    defaults so a previous backend sync isn't lost on a network failure.
    final localVendor    = p.getString('cp_vendor')          ?? '';
    final localModel     = p.getString('cp_model')           ?? '';
    final localSerial    = p.getString('cp_serialNumber')    ?? '';
    final localFw        = p.getString('cp_firmwareVersion') ?? '';
    final localConnCount = p.getInt('cp_connectorCount')     ?? 2;

    _settings = CpSettings(
      serverUrl:             serverUrl,
      chargePointId:         chargePointId,
      // Use last-known local values; empty strings mean "not yet synced"
      vendor:                localVendor.isNotEmpty  ? localVendor  : 'SimCo',
      model:                 localModel.isNotEmpty   ? localModel   : 'SimStation',
      serialNumber:          localSerial.isNotEmpty  ? localSerial  : 'SN-0001',
      firmwareVersion:       localFw.isNotEmpty      ? localFw      : '1.0.0',
      connectorCount:        localConnCount,
      heartbeatIntervalSec:  heartbeatIntervalSec,
      meterValueIntervalSec: meterValueIntervalSec,
      simulatedMaxPowerKw:   simulatedMaxPowerKw,
    );
    _initConnectors();
    notifyListeners();

    // ── Step 3: fetch identity from backend (source of truth) ──────────────
    try {
      final info = await ApiService().getChargePointInfo(serverUrl, chargePointId);

      if (info != null) {
        final backendVendor = info['vendor']          as String? ?? '';
        final backendModel  = info['model']           as String? ?? '';
        final backendSerial = info['serialNumber']    as String? ?? '';
        final backendFw     = info['firmwareVersion'] as String? ?? '';
        final connectors    = info['connectors']      as List<dynamic>? ?? [];
        final backendCount  = connectors.isNotEmpty ? connectors.length : localConnCount;

        // Only overwrite a field if the backend actually has a non-empty value.
        // This prevents a backend with partial data from wiping a good local value.
        _settings = _settings.copyWith(
          vendor:          backendVendor.isNotEmpty ? backendVendor : _settings.vendor,
          model:           backendModel.isNotEmpty  ? backendModel  : _settings.model,
          serialNumber:    backendSerial.isNotEmpty ? backendSerial : _settings.serialNumber,
          firmwareVersion: backendFw.isNotEmpty     ? backendFw     : _settings.firmwareVersion,
          connectorCount:  backendCount,
        );

        // ── Step 4: persist the synced values so the next cold-start uses them
        await p.setString('cp_vendor',          _settings.vendor);
        await p.setString('cp_model',           _settings.model);
        await p.setString('cp_serialNumber',    _settings.serialNumber);
        await p.setString('cp_firmwareVersion', _settings.firmwareVersion);
        await p.setInt   ('cp_connectorCount',  _settings.connectorCount);

        _initConnectors();
        notifyListeners();
        debugPrint('[CP] Identity loaded from backend: ${_settings.vendor} ${_settings.model} (${_settings.connectorCount} connectors)');
      } else {
        // CP not in DB yet — local SharedPreferences values already applied above.
        debugPrint('[CP] CP not found in backend — using local/default settings');
      }
    } catch (e) {
      // Network error — local SharedPreferences values already applied above.
      debugPrint('[CP] Backend unreachable during loadSettings: $e — using local settings');
    }
  }

  Future<void> saveSettings(CpSettings s) async {
    final urlChanged = s.serverUrl != _settings.serverUrl ||
        s.chargePointId != _settings.chargePointId;
    _settings = s;
    final p = await SharedPreferences.getInstance();
    await p.setString('cp_serverUrl',          s.serverUrl);
    await p.setString('cp_chargePointId',      s.chargePointId);
    await p.setString('cp_vendor',             s.vendor);
    await p.setString('cp_model',              s.model);
    await p.setString('cp_serialNumber',       s.serialNumber);
    await p.setString('cp_firmwareVersion',    s.firmwareVersion);
    await p.setInt   ('cp_connectorCount',     s.connectorCount);
    await p.setInt   ('cp_heartbeatInterval',  s.heartbeatIntervalSec);
    await p.setInt   ('cp_meterValueInterval', s.meterValueIntervalSec);
    await p.setDouble('cp_simulatedMaxPowerKw', s.simulatedMaxPowerKw);
    _initConnectors();
    notifyListeners();

    // Push updated identity to backend (it remains the source of truth)
    _pushIdentityToBackend(s);

    // Reconnect if connection-critical settings changed
    if (urlChanged && isConnected) {
      await disconnect();
      await Future.delayed(const Duration(milliseconds: 300));
      await connect();
    }
  }

  Future<void> _pushIdentityToBackend(CpSettings s) async {
    try {
      await ApiService().updateChargePointInfo(
        s.serverUrl,
        s.chargePointId,
        vendor:          s.vendor,
        model:           s.model,
        serialNumber:    s.serialNumber,
        firmwareVersion: s.firmwareVersion,
        connectorCount:  s.connectorCount,
      );
    } catch (e) {
      debugPrint('[CP] Identity push failed: $e');
    }
  }

  void _initConnectors() {
    // Preserve existing connector state when re-initialising (e.g. after settings change)
    final existing = {for (final c in _connectors) c.connectorId: c};
    _connectors = List.generate(
      _settings.connectorCount,
      (i) =>
          existing[i + 1] ??
          ConnectorState(
            connectorId: i + 1,
            status: ConnectorStatus.Unavailable,
          ),
    );
  }

  // =========================================================================
  // CONNECTION & BOOT
  // =========================================================================

  Future<void> connect() async {
    if (_connectionState == CpConnectionState.connecting ||
        _connectionState == CpConnectionState.connected) return;

    _lastError = null;
    try {
      await _hub.connect(_settings.serverUrl, _settings.chargePointId);
    } catch (e) {
      _lastError = 'Failed to connect: $e';
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _stopHeartbeat();
    _stopAllMeterTimers();
    _isBooted = false;
    await _hub.disconnect();
  }

  /// Sends BootNotification and StatusNotification for all connectors.
  /// Must be called after connect() succeeds.
  Future<void> boot() async {
    if (!isConnected) return;

    _addLog(OcppLogEntry(
      direction: OcppDirection.sent,
      action: 'BootNotification',
      payload: 'Vendor: ${_settings.vendor} | Model: ${_settings.model}',
    ));

    final frame = buildBootNotification(
      vendor: _settings.vendor,
      model: _settings.model,
      serialNumber: _settings.serialNumber,
      firmwareVersion: _settings.firmwareVersion,
    );

    final raw = await _hub.sendOcppMessage(frame);
    if (raw == null) {
      _lastError = 'BootNotification failed — no response';
      notifyListeners();
      return;
    }

    final result = parseFrame(raw);
    final status = result?.payload['status'] as String? ?? '';
    final interval =
        result?.payload['interval'] as int? ?? _settings.heartbeatIntervalSec;

    _addLog(OcppLogEntry(
      direction: OcppDirection.received,
      action: 'BootNotificationResponse',
      payload: 'Status: $status | Interval: ${interval}s',
    ));

    if (status == 'Accepted') {
      _isBooted = true;
      // Update heartbeat interval from backend response
      _settings = _settings.copyWith(heartbeatIntervalSec: interval);
      _startHeartbeat();

      // Mark all connectors Available and send StatusNotification
      for (final c in _connectors) {
        _updateConnector(c.connectorId,
            status: ConnectorStatus.Available, phase: SimulatorPhase.idle);
        await _sendStatusNotification(c.connectorId, 'Available', 'NoError');
      }
    }

    notifyListeners();
  }

  // =========================================================================
  // HEARTBEAT
  // =========================================================================

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: _settings.heartbeatIntervalSec),
      (_) => _sendHeartbeat(),
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _sendHeartbeat() async {
    if (!isConnected) return;
    final raw = await _hub.sendOcppMessage(buildHeartbeat());
    _addLog(OcppLogEntry(
      direction: OcppDirection.sent,
      action: 'Heartbeat',
      payload: raw != null ? 'OK' : 'No response',
    ));
  }

  // =========================================================================
  // AUTHORIZE
  // =========================================================================

  /// Returns the authorization status string ("Accepted", "Invalid", etc.)
  Future<String> authorize(String idTag) async {
    if (!isConnected) return 'Invalid';

    _addLog(OcppLogEntry(
      direction: OcppDirection.sent,
      action: 'Authorize',
      payload: 'idTag: $idTag',
    ));

    final raw = await _hub.sendOcppMessage(buildAuthorize(idTag));
    final result = parseFrame(raw ?? '');
    final status =
        result?.payload['idTagInfo']?['status'] as String? ?? 'Invalid';

    _addLog(OcppLogEntry(
      direction: OcppDirection.received,
      action: 'AuthorizeResponse',
      payload: 'Status: $status',
    ));

    return status;
  }

  // =========================================================================
  // START CHARGING SESSION (manual / card presented)
  // =========================================================================

  Future<bool> startSession(int connectorId, String idTag) async {
    final c = connector(connectorId);
    if (c == null || !isConnected) return false;
    if (c.phase != SimulatorPhase.idle) return false;

    // Move to Preparing
    _updateConnector(connectorId,
        status: ConnectorStatus.Preparing, phase: SimulatorPhase.preparing);
    await _sendStatusNotification(connectorId, 'Preparing', 'NoError');

    // Authorize the tag
    final authStatus = await authorize(idTag);
    if (authStatus != 'Accepted') {
      _updateConnector(connectorId,
          status: ConnectorStatus.Available, phase: SimulatorPhase.idle);
      await _sendStatusNotification(connectorId, 'Available', 'NoError');
      return false;
    }

    // Build a random starting meter value (simulates accumulated energy from previous sessions)
    final meterStart = 100000 + _rng.nextInt(900000); // 100–1000 kWh in Wh

    _addLog(OcppLogEntry(
      direction: OcppDirection.sent,
      action: 'StartTransaction',
      payload: 'Connector: $connectorId | Tag: $idTag | Meter: $meterStart Wh',
    ));

    final raw = await _hub.sendOcppMessage(buildStartTransaction(
      connectorId: connectorId,
      idTag: idTag,
      meterStart: meterStart,
    ));

    final result = parseFrame(raw ?? '');
    final txId = result?.payload['transactionId'] as int? ?? 0;
    final txStatus =
        result?.payload['idTagInfo']?['status'] as String? ?? 'Invalid';

    _addLog(OcppLogEntry(
      direction: OcppDirection.received,
      action: 'StartTransactionResponse',
      payload: 'TxId: $txId | Status: $txStatus',
    ));

    if (txId > 0 && txStatus == 'Accepted') {
      _updateConnector(
        connectorId,
        status: ConnectorStatus.Charging,
        phase: SimulatorPhase.charging,
        activeTransactionId: txId,
        activeIdTag: idTag,
        meterStartWh: meterStart,
        currentMeterWh: meterStart,
        sessionStartTime: DateTime.now(),
      );
      await _sendStatusNotification(connectorId, 'Charging', 'NoError');
      _startMeterTimer(connectorId);
      notifyListeners();
      return true;
    }

    // Transaction rejected — go back to Available
    _updateConnector(connectorId,
        status: ConnectorStatus.Available, phase: SimulatorPhase.idle);
    await _sendStatusNotification(connectorId, 'Available', 'NoError');
    return false;
  }

  // =========================================================================
  // STOP CHARGING SESSION (manual)
  // =========================================================================

  Future<void> stopSession(int connectorId, {String reason = 'Local'}) async {
    final c = connector(connectorId);
    if (c == null || c.activeTransactionId == null) return;

    _stopMeterTimer(connectorId);

    _updateConnector(connectorId,
        status: ConnectorStatus.Finishing, phase: SimulatorPhase.finishing);
    await _sendStatusNotification(connectorId, 'Finishing', 'NoError');

    _addLog(OcppLogEntry(
      direction: OcppDirection.sent,
      action: 'StopTransaction',
      payload:
          'TxId: ${c.activeTransactionId} | Meter: ${c.currentMeterWh} Wh | Reason: $reason',
    ));

    final raw = await _hub.sendOcppMessage(buildStopTransaction(
      transactionId: c.activeTransactionId!,
      idTag: c.activeIdTag ?? '',
      meterStop: c.currentMeterWh,
      reason: reason,
    ));

    final result = parseFrame(raw ?? '');
    _addLog(OcppLogEntry(
      direction: OcppDirection.received,
      action: 'StopTransactionResponse',
      payload: result?.payload.toString() ?? 'No response',
    ));

    _updateConnector(
      connectorId,
      status: ConnectorStatus.Available,
      phase: SimulatorPhase.idle,
      clearTransaction: true,
      clearSession: true,
    );
    await _sendStatusNotification(connectorId, 'Available', 'NoError');
    notifyListeners();
  }

  // =========================================================================
  // METER VALUES SIMULATION
  // =========================================================================

  void _startMeterTimer(int connectorId) {
    _meterTimers[connectorId]?.cancel();
    _meterTimers[connectorId] = Timer.periodic(
      Duration(seconds: _settings.meterValueIntervalSec),
      (_) => _sendMeterValues(connectorId),
    );
  }

  void _stopMeterTimer(int connectorId) {
    _meterTimers[connectorId]?.cancel();
    _meterTimers.remove(connectorId);
  }

  void _stopAllMeterTimers() {
    for (final t in _meterTimers.values) {
      t.cancel();
    }
    _meterTimers.clear();
  }

  Future<void> _sendMeterValues(int connectorId) async {
    final c = connector(connectorId);
    if (c == null || c.activeTransactionId == null || !isConnected) return;

    // Simulate realistic charging values with small variance
    final maxPowerW = _settings.simulatedMaxPowerKw * 1000;
    final powerW =
        maxPowerW * (0.88 + _rng.nextDouble() * 0.12); // 88–100% of max
    final voltageV = 230.0 + (_rng.nextDouble() * 6 - 3); // 227–233V
    final currentA = powerW / voltageV;

    // Energy accumulated since last sample (Wh = W × h)
    final intervalHours = _settings.meterValueIntervalSec / 3600.0;
    final energyThisInterval = (powerW * intervalHours).round();
    final newMeterWh = c.currentMeterWh + energyThisInterval;

    // Update local state
    final newHistory = [...c.powerHistory, powerW / 1000.0];
    if (newHistory.length > 30) newHistory.removeAt(0);

    _updateConnector(
      connectorId,
      currentMeterWh: newMeterWh,
      powerW: powerW,
      voltageV: voltageV,
      currentA: currentA,
      powerHistory: newHistory,
    );

    // Send to backend
    await _hub.sendOcppMessage(buildMeterValues(
      connectorId: connectorId,
      transactionId: c.activeTransactionId!,
      energyWh: newMeterWh.toDouble(),
      powerW: powerW,
      voltageV: voltageV,
      currentA: currentA,
    ));

    _addLog(OcppLogEntry(
      direction: OcppDirection.sent,
      action: 'MeterValues',
      payload:
          'Connector $connectorId | ${(newMeterWh / 1000.0).toStringAsFixed(3)} kWh | ${(powerW / 1000.0).toStringAsFixed(2)} kW',
    ));

    notifyListeners();
  }

  // =========================================================================
  // STATUS NOTIFICATION
  // =========================================================================

  Future<void> _sendStatusNotification(
      int connectorId, String status, String errorCode) async {
    if (!isConnected) return;
    final frame = buildStatusNotification(
      connectorId: connectorId,
      status: status,
      errorCode: errorCode,
    );
    await _hub.sendOcppMessage(frame);
    _addLog(OcppLogEntry(
      direction: OcppDirection.sent,
      action: 'StatusNotification',
      payload: 'Connector $connectorId → $status',
    ));
  }

  // =========================================================================
  // REMOTE COMMAND HANDLER (CSMS → CP)
  // The backend pushes OCPP CALL frames via the "OcppCommand" event.
  // We need to handle them and respond with a CALLRESULT.
  // =========================================================================

  void _listenToHub() {
    _stateSub = _hub.stateStream.listen((state) {
      _connectionState = state;
      if (state == CpConnectionState.disconnected) {
        _isBooted = false;
        _stopHeartbeat();
        _stopAllMeterTimers();
      }
      notifyListeners();
    });

    _commandSub = _hub.commandStream.listen(_handleRemoteCommand);
  }

  Future<void> _handleRemoteCommand(String rawFrame) async {
    final frame = parseFrame(rawFrame);
    if (frame == null || !frame.isCall) return;

    _addLog(OcppLogEntry(
      direction: OcppDirection.received,
      action: frame.action ?? 'Unknown',
      payload: frame.payload.toString(),
    ));

    final msgId = frame.messageId;
    final action = frame.action ?? '';
    final p = frame.payload;

    switch (action) {
      case 'RemoteStartTransaction':
        await _handleRemoteStart(msgId, p);
        break;
      case 'RemoteStopTransaction':
        await _handleRemoteStop(msgId, p);
        break;
      case 'ChangeAvailability':
        await _handleChangeAvailability(msgId, p);
        break;
      case 'Reset':
        await _handleReset(msgId, p);
        break;
      case 'UnlockConnector':
        await _handleUnlockConnector(msgId, p);
        break;
      case 'GetConfiguration':
        await _handleGetConfiguration(msgId, p);
        break;
      case 'ChangeConfiguration':
        await _handleChangeConfiguration(msgId, p);
        break;
      case 'TriggerMessage':
        await _handleTriggerMessage(msgId, p);
        break;
      case 'ClearCache':
        await _sendResult(msgId, {'status': 'Accepted'}, action);
        break;
      default:
        await _sendRawResult(buildCallError(
            msgId, 'NotImplemented', 'Action $action not implemented'));
        break;
    }
  }

  Future<void> _handleRemoteStart(String msgId, Map<String, dynamic> p) async {
    final idTag = p['idTag'] as String? ?? '';
    final connId = p['connectorId'] as int? ?? 1;

    final c = connector(connId) ??
        (_connectors.isNotEmpty ? _connectors.first : null);
    if (c == null || c.phase != SimulatorPhase.idle) {
      await _sendResult(
          msgId, {'status': 'Rejected'}, 'RemoteStartTransaction');
      return;
    }

    await _sendResult(msgId, {'status': 'Accepted'}, 'RemoteStartTransaction');
    // Start the session after ACK
    await Future.delayed(const Duration(milliseconds: 500));
    await startSession(c.connectorId, idTag);
  }

  Future<void> _handleRemoteStop(String msgId, Map<String, dynamic> p) async {
    final txId = p['transactionId'] as int? ?? 0;
    final c =
        _connectors.where((c) => c.activeTransactionId == txId).firstOrNull;

    if (c == null) {
      await _sendResult(msgId, {'status': 'Rejected'}, 'RemoteStopTransaction');
      return;
    }

    await _sendResult(msgId, {'status': 'Accepted'}, 'RemoteStopTransaction');
    await Future.delayed(const Duration(milliseconds: 500));
    await stopSession(c.connectorId, reason: 'Remote');
  }

  Future<void> _handleChangeAvailability(
      String msgId, Map<String, dynamic> p) async {
    final connId = p['connectorId'] as int? ?? 0;
    final type = p['type'] as String? ?? 'Operative';

    if (connId == 0) {
      // All connectors
      for (final c in _connectors) {
        if (c.phase == SimulatorPhase.idle) {
          final newStatus = type == 'Operative'
              ? ConnectorStatus.Available
              : ConnectorStatus.Unavailable;
          _updateConnector(c.connectorId, status: newStatus);
          await _sendStatusNotification(
              c.connectorId, newStatus.name, 'NoError');
        }
      }
    } else {
      final c = connector(connId);
      if (c != null && c.phase == SimulatorPhase.idle) {
        final newStatus = type == 'Operative'
            ? ConnectorStatus.Available
            : ConnectorStatus.Unavailable;
        _updateConnector(connId, status: newStatus);
        await _sendStatusNotification(connId, newStatus.name, 'NoError');
      }
    }

    await _sendResult(msgId, {'status': 'Accepted'}, 'ChangeAvailability');
  }

  Future<void> _handleReset(String msgId, Map<String, dynamic> p) async {
    final type = p['type'] as String? ?? 'Soft';
    await _sendResult(msgId, {'status': 'Accepted'}, 'Reset');
    _addLog(OcppLogEntry(
      direction: OcppDirection.received,
      action: 'Reset',
      payload: 'Type: $type — simulating reboot...',
    ));

    // Simulate reboot: stop active sessions, disconnect, reconnect
    await Future.delayed(const Duration(seconds: 2));
    _stopHeartbeat();
    _stopAllMeterTimers();

    // Stop all active sessions gracefully (Soft) or immediately (Hard)
    if (type == 'Soft') {
      for (final c in List.from(_connectors)) {
        if (c.isCharging) await stopSession(c.connectorId, reason: 'Reboot');
      }
    }

    _isBooted = false;
    for (int i = 0; i < _connectors.length; i++) {
      _connectors[i] = ConnectorState(
        connectorId: _connectors[i].connectorId,
        status: ConnectorStatus.Unavailable,
      );
    }
    notifyListeners();

    await Future.delayed(const Duration(seconds: 3));
    if (!isConnected) await connect(); // reconnect if dropped during reset
    await Future.delayed(const Duration(milliseconds: 300));
    await boot(); // Re-send BootNotification
  }

  Future<void> _handleUnlockConnector(
      String msgId, Map<String, dynamic> p) async {
    final connId = p['connectorId'] as int? ?? 1;
    final c = connector(connId);
    final status = (c != null && !c.isCharging) ? 'Unlocked' : 'UnlockFailed';
    await _sendResult(msgId, {'status': status}, 'UnlockConnector');
  }

  Future<void> _handleGetConfiguration(
      String msgId, Map<String, dynamic> p) async {
    await _sendResult(
        msgId,
        {
          'configurationKey': [
            {
              'key': 'HeartbeatInterval',
              'readonly': false,
              'value': '${_settings.heartbeatIntervalSec}'
            },
            {
              'key': 'MeterValueSampleInterval',
              'readonly': false,
              'value': '${_settings.meterValueIntervalSec}'
            },
            {
              'key': 'NumberOfConnectors',
              'readonly': true,
              'value': '${_settings.connectorCount}'
            },
            {
              'key': 'ChargePointVendor',
              'readonly': true,
              'value': _settings.vendor
            },
            {
              'key': 'ChargePointModel',
              'readonly': true,
              'value': _settings.model
            },
            {
              'key': 'FirmwareVersion',
              'readonly': true,
              'value': _settings.firmwareVersion
            },
          ],
          'unknownKey': [],
        },
        'GetConfiguration');
  }

  Future<void> _handleChangeConfiguration(
      String msgId, Map<String, dynamic> p) async {
    final key = p['key'] as String? ?? '';
    final value = p['value'] as String? ?? '';

    String status = 'Accepted';
    switch (key) {
      case 'HeartbeatInterval':
        final v = int.tryParse(value);
        if (v != null && v > 0) {
          _settings = _settings.copyWith(heartbeatIntervalSec: v);
          _startHeartbeat(); // Restart with new interval
        }
        break;
      case 'MeterValueSampleInterval':
        final v = int.tryParse(value);
        if (v != null && v > 0) {
          _settings = _settings.copyWith(meterValueIntervalSec: v);
        }
        break;
      default:
        status = 'NotSupported';
    }

    await _sendResult(msgId, {'status': status}, 'ChangeConfiguration');
  }

  Future<void> _handleTriggerMessage(
      String msgId, Map<String, dynamic> p) async {
    final msg = p['requestedMessage'] as String? ?? '';
    final connId = p['connectorId'] as int?;

    await _sendResult(msgId, {'status': 'Accepted'}, 'TriggerMessage');

    // Immediately send the requested message
    switch (msg) {
      case 'Heartbeat':
        await _sendHeartbeat();
        break;
      case 'StatusNotification':
        final id = connId ??
            (_connectors.isNotEmpty ? _connectors.first.connectorId : 1);
        final c = connector(id);
        if (c != null)
          await _sendStatusNotification(id, c.status.name, 'NoError');
        break;
      case 'BootNotification':
        await boot();
        break;
      case 'MeterValues':
        if (connId != null) await _sendMeterValues(connId);
        break;
    }
  }

  // =========================================================================
  // HELPERS
  // =========================================================================

  Future<void> _sendResult(
      String msgId, Map<String, dynamic> payload, String action) async {
    final raw = buildCallResult(msgId, payload);
    await _sendRawResult(raw);
    _addLog(OcppLogEntry(
      direction: OcppDirection.sent,
      action: '${action}Response',
      payload: payload.toString(),
    ));
  }

  Future<void> _sendRawResult(String raw) async {
    await _hub.sendOcppMessage(raw);
  }

  void _updateConnector(
    int connectorId, {
    ConnectorStatus? status,
    SimulatorPhase? phase,
    int? activeTransactionId,
    String? activeIdTag,
    DateTime? sessionStartTime,
    int? meterStartWh,
    int? currentMeterWh,
    double? powerW,
    double? voltageV,
    double? currentA,
    List<double>? powerHistory,
    bool clearTransaction = false,
    bool clearSession = false,
  }) {
    final idx = _connectors.indexWhere((c) => c.connectorId == connectorId);
    if (idx < 0) return;
    _connectors[idx] = _connectors[idx].copyWith(
      status: status,
      phase: phase,
      activeTransactionId: activeTransactionId,
      activeIdTag: activeIdTag,
      sessionStartTime: sessionStartTime,
      meterStartWh: meterStartWh,
      currentMeterWh: currentMeterWh,
      powerW: powerW,
      voltageV: voltageV,
      currentA: currentA,
      powerHistory: powerHistory,
      clearTransaction: clearTransaction,
      clearSession: clearSession,
    );
    notifyListeners();
  }

  void _addLog(OcppLogEntry entry) {
    _log.insert(0, entry);
    if (_log.length > 100) _log.removeLast();
    notifyListeners();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _commandSub?.cancel();
    _stopHeartbeat();
    _stopAllMeterTimers();
    _hub.dispose();
    super.dispose();
  }
}