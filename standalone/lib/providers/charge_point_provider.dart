// lib/providers/charge_point_provider.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/ocpp_models.dart';
import '../services/ocpp_service.dart';

class ChargePointProvider extends ChangeNotifier {
  final OcppService _ocpp = OcppService();
  final _random = Random();

  // ─── Config & State ──────────────────────────────────────────────────────────
  ChargePointConfig config = ChargePointConfig();
  CpConnectionState connectionState = CpConnectionState.disconnected;
  ChargePointStatus chargePointStatus = ChargePointStatus.available;
  ChargePointErrorCode errorCode = ChargePointErrorCode.noError;

  List<ConnectorModel> connectors = [];
  List<LogEntry> logs = [];

  Timer? _heartbeatTimer;
  final Map<int, Timer> _meterValueTimers = {};
  final Map<int, Timer> _chargingSimTimers = {};

  int _transactionCounter = 1000;

  // ─── Init ─────────────────────────────────────────────────────────────────────

  ChargePointProvider() {
    _initConnectors();
    _setupOcppCallbacks();
    _registerRemoteCommandHandlers();
  }

  void _initConnectors() {
    connectors = List.generate(
      config.numberOfConnectors,
      (i) => ConnectorModel(id: i + 1),
    );
  }

  void _setupOcppCallbacks() {
    _ocpp.onLog = (entry) {
      logs.add(entry);
      if (logs.length > 500) logs.removeAt(0);
      notifyListeners();
    };
    _ocpp.onConnected = () {
      connectionState = CpConnectionState.connected;
      notifyListeners();
      _sendBootNotification();
    };
    _ocpp.onDisconnected = () {
      connectionState = CpConnectionState.disconnected;
      _stopAllTimers();
      notifyListeners();
    };
  }

  void _registerRemoteCommandHandlers() {
    _ocpp.registerCommandHandler('RemoteStartTransaction', _handleRemoteStart);
    _ocpp.registerCommandHandler('RemoteStopTransaction', _handleRemoteStop);
    _ocpp.registerCommandHandler('ChangeAvailability', _handleChangeAvailability);
    _ocpp.registerCommandHandler('Reset', _handleReset);
    _ocpp.registerCommandHandler('GetConfiguration', _handleGetConfiguration);
    _ocpp.registerCommandHandler('ChangeConfiguration', _handleChangeConfiguration);
    _ocpp.registerCommandHandler('TriggerMessage', _handleTriggerMessage);
    _ocpp.registerCommandHandler('UnlockConnector', _handleUnlockConnector);
    _ocpp.registerCommandHandler('ClearCache', _handleClearCache);
  }

  // ─── Connection Control ──────────────────────────────────────────────────────

  Future<void> connect() async {
    if (connectionState != CpConnectionState.disconnected) return;
    connectionState = CpConnectionState.connecting;
    notifyListeners();
    try {
      await _ocpp.connect(config);
    } catch (e) {
      connectionState = CpConnectionState.disconnected;
      notifyListeners();
    }
  }

  void disconnect() {
    _ocpp.disconnect();
    _stopAllTimers();
    connectionState = CpConnectionState.disconnected;
    notifyListeners();
  }

  // ─── OCPP Flows ───────────────────────────────────────────────────────────────

  Future<void> _sendBootNotification() async {
    try {
      final resp = await _ocpp.sendCall('BootNotification', {
        'chargePointVendor': config.vendor,
        'chargePointModel': config.model,
        'chargePointSerialNumber': config.serialNumber,
        'firmwareVersion': config.firmwareVersion,
        'chargeBoxSerialNumber': config.chargePointId,
      });

      final status = resp['status'] as String? ?? 'Rejected';
      if (status == 'Accepted') {
        final interval = resp['interval'] as int? ?? config.heartbeatInterval;
        config.heartbeatInterval = interval;
        _startHeartbeat();
        _sendStatusNotifications();
      }
    } catch (e) {
      _addSystemLog('BootNotification failed: $e', isError: true);
    }
  }

  Future<void> sendHeartbeat() async {
    if (!_ocpp.isConnected) return;
    try {
      await _ocpp.sendCall('Heartbeat', {});
    } catch (_) {}
  }

  Future<void> _sendStatusNotifications() async {
    await _sendStatusNotification(0, chargePointStatus, errorCode);
    for (final c in connectors) {
      await _sendStatusNotification(
        c.id,
        _connectorStatusToCP(c.status),
        ChargePointErrorCode.noError,
      );
    }
  }

  Future<void> _sendStatusNotification(
    int connectorId,
    ChargePointStatus status,
    ChargePointErrorCode err,
  ) async {
    if (!_ocpp.isConnected) return;
    try {
      await _ocpp.sendCall('StatusNotification', {
        'connectorId': connectorId,
        'errorCode': _errorCodeToStr(err),
        'status': _cpStatusToStr(status),
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  // ─── Authorize ────────────────────────────────────────────────────────────────

  Future<AuthorizationStatus> authorize(String idTag) async {
    try {
      final resp = await _ocpp.sendCall('Authorize', {'idTag': idTag});
      final idInfo = resp['idTagInfo'] as Map<String, dynamic>? ?? {};
      final statusStr = idInfo['status'] as String? ?? 'Invalid';
      return _parseAuthStatus(statusStr);
    } catch (_) {
      return AuthorizationStatus.invalid;
    }
  }

  // ─── Start Transaction ────────────────────────────────────────────────────────

  Future<bool> startTransaction(int connectorId, String idTag) async {
    final connector = _getConnector(connectorId);
    if (connector == null) return false;
    if (connector.status != ConnectorStatus.available) return false;

    _updateConnector(connectorId, status: ConnectorStatus.occupied);
    await _sendStatusNotification(
        connectorId, ChargePointStatus.preparing, ChargePointErrorCode.noError);

    final authStatus = await authorize(idTag);
    if (authStatus != AuthorizationStatus.accepted) {
      _updateConnector(connectorId, status: ConnectorStatus.available);
      await _sendStatusNotification(
          connectorId, ChargePointStatus.available, ChargePointErrorCode.noError);
      return false;
    }

    try {
      final resp = await _ocpp.sendCall('StartTransaction', {
        'connectorId': connectorId,
        'idTag': idTag,
        'meterStart': (connector.energyDeliveredKwh * 1000).round(),
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      final idInfo = resp['idTagInfo'] as Map<String, dynamic>? ?? {};
      final status = idInfo['status'] as String? ?? 'Invalid';
      if (status != 'Accepted') {
        _updateConnector(connectorId, status: ConnectorStatus.available);
        return false;
      }

      final txId =
          (resp['transactionId'] as int? ?? _transactionCounter++).toString();
      _updateConnector(
        connectorId,
        status: ConnectorStatus.occupied,
        activeTransactionId: txId,
        authorizedIdTag: idTag,
        sessionStart: DateTime.now(),
        currentPowerKw: _randomPower(),
      );

      await _sendStatusNotification(
          connectorId, ChargePointStatus.charging, ChargePointErrorCode.noError);
      _startMeterValues(connectorId);
      notifyListeners();
      return true;
    } catch (e) {
      _updateConnector(connectorId, status: ConnectorStatus.available);
      return false;
    }
  }

  // ─── Stop Transaction ─────────────────────────────────────────────────────────

  Future<void> stopTransaction(int connectorId, {String reason = 'Local'}) async {
    final connector = _getConnector(connectorId);
    if (connector == null || connector.activeTransactionId == null) return;

    _chargingSimTimers[connectorId]?.cancel();
    _meterValueTimers[connectorId]?.cancel();

    final txId = int.tryParse(connector.activeTransactionId!) ?? 0;
    final meterStop = (connector.energyDeliveredKwh * 1000).round();

    await _sendMeterValues(connectorId);

    try {
      await _ocpp.sendCall('StopTransaction', {
        'transactionId': txId,
        'idTag': connector.authorizedIdTag,
        'meterStop': meterStop,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'reason': reason,
        'transactionData': _buildTransactionData(connector),
      });
    } catch (_) {}

    _updateConnector(
      connectorId,
      status: ConnectorStatus.available,
      activeTransactionId: '',
      authorizedIdTag: '',
      currentPowerKw: 0,
      energyDeliveredKwh: 0,
      clearSession: true,
    );
    _getConnector(connectorId)?.meterHistory.clear();

    await _sendStatusNotification(
        connectorId, ChargePointStatus.available, ChargePointErrorCode.noError);
    notifyListeners();
  }

  // ─── Meter Values ─────────────────────────────────────────────────────────────

  void _startMeterValues(int connectorId) {
    _meterValueTimers[connectorId]?.cancel();
    _chargingSimTimers[connectorId]?.cancel();

    _startChargingSimulation(connectorId);

    _meterValueTimers[connectorId] = Timer.periodic(
      Duration(seconds: config.meterValueInterval),
      (_) => _sendMeterValues(connectorId),
    );
  }

  void _startChargingSimulation(int connectorId) {
    _chargingSimTimers[connectorId] = Timer.periodic(
        const Duration(seconds: 1), (_) {
      final connector = _getConnector(connectorId);
      if (connector == null || connector.activeTransactionId == null) {
        _chargingSimTimers[connectorId]?.cancel();
        return;
      }
      final power = (connector.currentPowerKw +
              (_random.nextDouble() - 0.5) * 0.5)
          .clamp(1.0, config.maxPowerKw);
      final addedEnergy = power / 3600;
      final newEnergy = connector.energyDeliveredKwh + addedEnergy;

      final sample = MeterSample(
        timestamp: DateTime.now(),
        powerKw: power,
        energyKwh: newEnergy,
        voltage: 230 + (_random.nextDouble() - 0.5) * 4,
        currentA: (power * 1000) / 230,
      );

      connector.currentPowerKw = power;
      connector.energyDeliveredKwh = newEnergy;
      connector.meterHistory.add(sample);
      if (connector.meterHistory.length > 120) connector.meterHistory.removeAt(0);

      notifyListeners();
    });
  }

  Future<void> _sendMeterValues(int connectorId) async {
    final connector = _getConnector(connectorId);
    if (connector == null || !_ocpp.isConnected) return;

    final txId = int.tryParse(connector.activeTransactionId ?? '') ?? 0;
    try {
      await _ocpp.sendCall('MeterValues', {
        'connectorId': connectorId,
        'transactionId': txId,
        'meterValue': [
          {
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'sampledValue': [
              {
                'value': (connector.energyDeliveredKwh * 1000).toStringAsFixed(2),
                'measurand': 'Energy.Active.Import.Register',
                'unit': 'Wh',
              },
              {
                'value': (connector.currentPowerKw * 1000).toStringAsFixed(2),
                'measurand': 'Power.Active.Import',
                'unit': 'W',
              },
              {
                'value': connector.meterHistory.isNotEmpty
                    ? connector.meterHistory.last.voltage.toStringAsFixed(1)
                    : '230.0',
                'measurand': 'Voltage',
                'unit': 'V',
              },
              {
                'value': connector.meterHistory.isNotEmpty
                    ? connector.meterHistory.last.currentA.toStringAsFixed(2)
                    : '0.00',
                'measurand': 'Current.Import',
                'unit': 'A',
              },
            ],
          }
        ],
      });
    } catch (_) {}
  }

  // ─── Heartbeat Timer ──────────────────────────────────────────────────────────

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: config.heartbeatInterval),
      (_) => sendHeartbeat(),
    );
  }

  void _stopAllTimers() {
    _heartbeatTimer?.cancel();
    for (final t in _meterValueTimers.values) t.cancel();
    for (final t in _chargingSimTimers.values) t.cancel();
    _meterValueTimers.clear();
    _chargingSimTimers.clear();
  }

  // ─── Remote Command Handlers ──────────────────────────────────────────────────

  void _handleRemoteStart(
      String action, Map<String, dynamic> payload, String msgId) {
    final connectorId = payload['connectorId'] as int? ?? 1;
    final idTag = payload['idTag'] as String? ?? 'REMOTE-TAG';
    _ocpp.sendCallResult(msgId, {'status': 'Accepted'});
    startTransaction(connectorId, idTag);
  }

  void _handleRemoteStop(
      String action, Map<String, dynamic> payload, String msgId) {
    final txId = payload['transactionId']?.toString();
    final connector =
        connectors.where((c) => c.activeTransactionId == txId).firstOrNull;
    if (connector != null) {
      _ocpp.sendCallResult(msgId, {'status': 'Accepted'});
      stopTransaction(connector.id, reason: 'Remote');
    } else {
      _ocpp.sendCallResult(msgId, {'status': 'Rejected'});
    }
  }

  void _handleChangeAvailability(
      String action, Map<String, dynamic> payload, String msgId) {
    final connectorId = payload['connectorId'] as int? ?? 0;
    final type = payload['type'] as String? ?? 'Operative';
    final newStatus =
        type == 'Inoperative' ? ConnectorStatus.unavailable : ConnectorStatus.available;

    if (connectorId == 0) {
      for (final c in connectors) {
        _updateConnector(c.id, status: newStatus);
      }
    } else {
      _updateConnector(connectorId, status: newStatus);
    }
    _ocpp.sendCallResult(msgId, {'status': 'Accepted'});
    // Notify status change for each affected connector
    if (connectorId == 0) {
      for (final c in connectors) {
        _sendStatusNotification(c.id, _connectorStatusToCP(newStatus),
            ChargePointErrorCode.noError);
      }
    } else {
      _sendStatusNotification(connectorId, _connectorStatusToCP(newStatus),
          ChargePointErrorCode.noError);
    }
    notifyListeners();
  }

  void _handleReset(
      String action, Map<String, dynamic> payload, String msgId) {
    _ocpp.sendCallResult(msgId, {'status': 'Accepted'});
    Future.delayed(const Duration(seconds: 2), () async {
      disconnect();
      await Future.delayed(const Duration(seconds: 3));
      await connect();
    });
  }

  void _handleGetConfiguration(
      String action, Map<String, dynamic> payload, String msgId) {
    _ocpp.sendCallResult(msgId, {
      'configurationKey': [
        {'key': 'HeartbeatInterval', 'readonly': false, 'value': '${config.heartbeatInterval}'},
        {'key': 'MeterValueSampleInterval', 'readonly': false, 'value': '${config.meterValueInterval}'},
        {'key': 'NumberOfConnectors', 'readonly': true, 'value': '${config.numberOfConnectors}'},
        {'key': 'MaxChargingProfilesInstalled', 'readonly': true, 'value': '10'},
        {'key': 'ChargePointVendor', 'readonly': true, 'value': config.vendor},
        {'key': 'ChargePointModel', 'readonly': true, 'value': config.model},
      ],
      'unknownKey': [],
    });
  }

  void _handleChangeConfiguration(
      String action, Map<String, dynamic> payload, String msgId) {
    final key = payload['key'] as String?;
    final value = payload['value'] as String?;
    if (key == 'HeartbeatInterval' && value != null) {
      config.heartbeatInterval = int.tryParse(value) ?? config.heartbeatInterval;
      _startHeartbeat();
    } else if (key == 'MeterValueSampleInterval' && value != null) {
      config.meterValueInterval =
          int.tryParse(value) ?? config.meterValueInterval;
    }
    _ocpp.sendCallResult(msgId, {'status': 'Accepted'});
    notifyListeners();
  }

  void _handleTriggerMessage(
      String action, Map<String, dynamic> payload, String msgId) {
    final requestedMsg = payload['requestedMessage'] as String? ?? '';
    _ocpp.sendCallResult(msgId, {'status': 'Accepted'});
    switch (requestedMsg) {
      case 'Heartbeat':
        sendHeartbeat();
        break;
      case 'StatusNotification':
        _sendStatusNotifications();
        break;
      case 'BootNotification':
        _sendBootNotification();
        break;
    }
  }

  void _handleUnlockConnector(
    String action, Map<String, dynamic> payload, String msgId) {
    final connectorId = payload['connectorId'] as int? ?? 1;
    final connector = _getConnector(connectorId);
    if (connector?.activeTransactionId != null) {
      // Can't unlock while charging
      _ocpp.sendCallResult(msgId, {'status': 'UnlockFailed'});
    } else {
      // Force connector back to Available and send StatusNotification
      _ocpp.sendCallResult(msgId, {'status': 'Unlocked'});
      _updateConnector(connectorId,
          status: ConnectorStatus.available,
          clearSession: true);
      _sendStatusNotification(
          connectorId, ChargePointStatus.available, ChargePointErrorCode.noError);
      notifyListeners();
    }
  }

  void _handleClearCache(
      String action, Map<String, dynamic> payload, String msgId) {
    _ocpp.sendCallResult(msgId, {'status': 'Accepted'});
  }

  // ─── Remote Command Injection (from UI) ──────────────────────────────────────

  void injectRemoteCommand(String action, Map<String, dynamic> payload) {
    if (!_ocpp.isConnected) return;
    _ocpp.simulateRemoteCommand(action, payload);
  }

  // ─── Fault Simulation ────────────────────────────────────────────────────────

  Future<void> simulateFault(int connectorId, ChargePointErrorCode err) async {
    errorCode = err;
    chargePointStatus = ChargePointStatus.faulted;
    _updateConnector(connectorId, status: ConnectorStatus.faulted);
    await _sendStatusNotification(connectorId, ChargePointStatus.faulted, err);
    notifyListeners();
  }

  Future<void> clearFault(int connectorId) async {
    errorCode = ChargePointErrorCode.noError;
    chargePointStatus = ChargePointStatus.available;
    _updateConnector(connectorId, status: ConnectorStatus.available);
    await _sendStatusNotification(
        connectorId, ChargePointStatus.available, ChargePointErrorCode.noError);
    notifyListeners();
  }

  // ─── Config Update ────────────────────────────────────────────────────────────

  void updateConfig(ChargePointConfig newConfig) {
    config = newConfig;
    _initConnectors();
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────────

  ConnectorModel? _getConnector(int id) {
    try {
      return connectors.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  void _updateConnector(
    int id, {
    ConnectorStatus? status,
    double? currentPowerKw,
    double? energyDeliveredKwh,
    String? activeTransactionId,
    String? authorizedIdTag,
    DateTime? sessionStart,
    bool clearSession = false,
  }) {
    final idx = connectors.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    final c = connectors[idx];
    connectors[idx] = ConnectorModel(
      id: c.id,
      status: status ?? c.status,
      currentPowerKw: currentPowerKw ?? c.currentPowerKw,
      energyDeliveredKwh: energyDeliveredKwh ?? c.energyDeliveredKwh,
      activeTransactionId: clearSession
          ? null
          : (activeTransactionId == ''
              ? null
              : (activeTransactionId ?? c.activeTransactionId)),
      authorizedIdTag: clearSession
          ? null
          : (authorizedIdTag == ''
              ? null
              : (authorizedIdTag ?? c.authorizedIdTag)),
      sessionStart: clearSession ? null : (sessionStart ?? c.sessionStart),
      meterHistory: c.meterHistory,
    );
    notifyListeners();
  }

  double _randomPower() => 5 + _random.nextDouble() * (config.maxPowerKw - 5);

  ChargePointStatus _connectorStatusToCP(ConnectorStatus s) {
    switch (s) {
      case ConnectorStatus.available:
        return ChargePointStatus.available;
      case ConnectorStatus.occupied:
        return ChargePointStatus.charging;
      case ConnectorStatus.reserved:
        return ChargePointStatus.reserved;
      case ConnectorStatus.unavailable:
        return ChargePointStatus.unavailable;
      case ConnectorStatus.faulted:
        return ChargePointStatus.faulted;
    }
  }

  AuthorizationStatus _parseAuthStatus(String s) {
    switch (s) {
      case 'Accepted':
        return AuthorizationStatus.accepted;
      case 'Blocked':
        return AuthorizationStatus.blocked;
      case 'Expired':
        return AuthorizationStatus.expired;
      case 'ConcurrentTx':
        return AuthorizationStatus.concurrentTx;
      default:
        return AuthorizationStatus.invalid;
    }
  }

  String _cpStatusToStr(ChargePointStatus s) {
    switch (s) {
      case ChargePointStatus.available:
        return 'Available';
      case ChargePointStatus.preparing:
        return 'Preparing';
      case ChargePointStatus.charging:
        return 'Charging';
      case ChargePointStatus.suspendedEVSE:
        return 'SuspendedEVSE';
      case ChargePointStatus.suspendedEV:
        return 'SuspendedEV';
      case ChargePointStatus.finishing:
        return 'Finishing';
      case ChargePointStatus.reserved:
        return 'Reserved';
      case ChargePointStatus.unavailable:
        return 'Unavailable';
      case ChargePointStatus.faulted:
        return 'Faulted';
    }
  }

  String _errorCodeToStr(ChargePointErrorCode e) {
    switch (e) {
      case ChargePointErrorCode.noError:
        return 'NoError';
      case ChargePointErrorCode.connectorLockFailure:
        return 'ConnectorLockFailure';
      case ChargePointErrorCode.evCommunicationError:
        return 'EVCommunicationError';
      case ChargePointErrorCode.groundFailure:
        return 'GroundFailure';
      case ChargePointErrorCode.highTemperature:
        return 'HighTemperature';
      case ChargePointErrorCode.internalError:
        return 'InternalError';
      case ChargePointErrorCode.overCurrentFailure:
        return 'OverCurrentFailure';
      case ChargePointErrorCode.overVoltage:
        return 'OverVoltage';
      case ChargePointErrorCode.underVoltage:
        return 'UnderVoltage';
      case ChargePointErrorCode.powerMeterFailure:
        return 'PowerMeterFailure';
      default:
        return 'OtherError';
    }
  }

  List<Map<String, dynamic>> _buildTransactionData(ConnectorModel c) {
    return [
      {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'sampledValue': [
          {
            'value': (c.energyDeliveredKwh * 1000).toStringAsFixed(2),
            'measurand': 'Energy.Active.Import.Register',
            'unit': 'Wh',
            'context': 'Transaction.End',
          }
        ],
      }
    ];
  }

  void _addSystemLog(String msg, {bool isError = false}) {
    logs.add(LogEntry(
      timestamp: DateTime.now(),
      direction: LogDirection.system,
      message: msg,
      isError: isError,
    ));
    notifyListeners();
  }

  @override
  void dispose() {
    _stopAllTimers();
    _ocpp.disconnect();
    super.dispose();
  }
}
