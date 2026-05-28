// lib/providers/csms_provider.dart
// Central state for the entire CSMS app.
// Owns the SignalR connection, all charge point/transaction data,
// and exposes actions the UI can call.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/csms_models.dart';
import '../services/csms_signalr_service.dart';
import '../services/api_service.dart';

class CsmsProvider extends ChangeNotifier {
  final CsmsSignalRService _hub = CsmsSignalRService();
  final ApiService _api = ApiService();

  // ─── Connection state ────────────────────────────────────────────────────
  CsmsConnectionState _connectionState = CsmsConnectionState.disconnected;
  CsmsConnectionState get connectionState => _connectionState;
  bool get isConnected => _connectionState == CsmsConnectionState.connected;

  String _serverUrl = 'http://localhost:5000';
  String get serverUrl => _serverUrl;

  // ─── Charge Points ───────────────────────────────────────────────────────
  final Map<String, ChargePointModel> _chargePoints = {};
  List<ChargePointModel> get chargePoints =>
      _chargePoints.values.toList()
        ..sort((a, b) => a.chargePointId.compareTo(b.chargePointId));

  // ─── Transactions ────────────────────────────────────────────────────────
  final Map<int, TransactionModel> _activeTransactions = {};
  List<TransactionModel> get activeTransactions =>
      _activeTransactions.values.toList()
        ..sort((a, b) => b.startTime.compareTo(a.startTime));

  // ─── Tags ────────────────────────────────────────────────────────────────
  List<IdTagModel> _tags = [];
  List<IdTagModel> get tags => _tags;

  // ─── Activity log (last 100 events shown in the Log screen) ──────────────
  final List<ActivityLogEntry> _activityLog = [];
  List<ActivityLogEntry> get activityLog => List.unmodifiable(_activityLog);

  // ─── Loading flags ───────────────────────────────────────────────────────
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _lastError;
  String? get lastError => _lastError;

  StreamSubscription? _stateSub;
  StreamSubscription? _messageSub;

  // ── Auth result stream — UI listens to this for real-time tag feedback ──
  final _authResultController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get authResultStream => _authResultController.stream;

  CsmsProvider() {
    _listenToHub();
  }

  // ─── Settings persistence ─────────────────────────────────────────────────

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString('serverUrl') ?? 'http://localhost:5000';
    _api.setBaseUrl(_serverUrl);
    notifyListeners();
  }

  Future<void> saveServerUrl(String url) async {
    _serverUrl = url;
    _api.setBaseUrl(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverUrl', url);
    notifyListeners();
  }

  // ─── Connection ───────────────────────────────────────────────────────────

  Future<void> connect() async {
    if (_connectionState == CsmsConnectionState.connecting ||
        _connectionState == CsmsConnectionState.connected) return;

    _lastError = null;
    try {
      await _hub.connect(_serverUrl);
      await loadInitialData();
    } catch (e) {
      _lastError = 'Failed to connect: $e';
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _hub.disconnect();
  }

  // ─── Initial data load ────────────────────────────────────────────────────

  Future<void> loadInitialData() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Load charge points + connectors
      final cpList = await _hub.getAllChargePoints();
      if (cpList != null) {
        for (final cp in cpList) {
          final model = ChargePointModel.fromJson(cp as Map<String, dynamic>);
          _chargePoints[model.chargePointId] = model;
        }
      }

      // Load active transactions
      final txList = await _hub.getActiveTransactions();
      if (txList != null) {
        for (final tx in txList) {
          final model = TransactionModel.fromJson(tx as Map<String, dynamic>);
          _activeTransactions[model.transactionId] = model;
        }
      }

      // Load tags via REST
      await refreshTags();
    } catch (e) {
      debugPrint('[CSMS] Initial load failed: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // ─── Hub Event Listener ───────────────────────────────────────────────────

  void _listenToHub() {
    _stateSub = _hub.stateStream.listen((state) {
      _connectionState = state;
      notifyListeners();
    });

    _messageSub = _hub.messageStream.listen(_handleEvent);
  }

  void _handleEvent(Map<String, dynamic> data) {
    final event = data['event'] as String;

    switch (event) {
      case 'ChargePointBooted':
        _onChargePointBooted(data);
        break;
      case 'ChargePointOffline':
        _onChargePointOffline(data);
        break;
      case 'HeartbeatReceived':
        _onHeartbeat(data);
        break;
      case 'AuthorizeRequest':
        _onAuthorizeRequest(data);
        break;
      case 'TransactionStarted':
        _onTransactionStarted(data);
        break;
      case 'TransactionStopped':
        _onTransactionStopped(data);
        break;
      case 'MeterValuesUpdated':
        _onMeterValues(data);
        break;
      case 'ChargePointStatusUpdate':
        _onStatusUpdate(data);
        break;
      case 'ChargePointUpdated':
        _onChargePointUpdated(data);
        break;
    }
  }

  // ─── Event Handlers ───────────────────────────────────────────────────────

  void _onChargePointBooted(Map<String, dynamic> d) {
    final cpId = d['chargePointId'] as String? ?? '';
    final existing = _chargePoints[cpId];

    _chargePoints[cpId] = ChargePointModel(
      chargePointId:   cpId,
      vendor:          d['vendor'] ?? existing?.vendor ?? '',
      model:           d['model'] ?? existing?.model ?? '',
      serialNumber:    d['serialNumber'] ?? existing?.serialNumber ?? '',
      firmwareVersion: d['firmwareVersion'] ?? existing?.firmwareVersion ?? '',
      isOnline:        true,
      lastHeartbeat:   DateTime.now(),
      lastBootTime:    DateTime.now(),
      connectors:      existing?.connectors ?? [],
    );

    _addLog(ActivityLogEntry(
      type:    LogType.boot,
      cpId:    cpId,
      message: 'Charge point booted (${d['vendor']} ${d['model']})',
    ));
    notifyListeners();
  }

  void _onChargePointOffline(Map<String, dynamic> d) {
    final cpId = d['chargePointId'] as String? ?? '';
    final cp = _chargePoints[cpId];
    if (cp != null) {
      _chargePoints[cpId] = cp.copyWith(isOnline: false);
    }
    _addLog(ActivityLogEntry(type: LogType.offline, cpId: cpId, message: 'Charge point went offline'));
    notifyListeners();
  }

  void _onHeartbeat(Map<String, dynamic> d) {
    final cpId = d['chargePointId'] as String? ?? '';
    final cp = _chargePoints[cpId];
    if (cp != null) {
      _chargePoints[cpId] = cp.copyWith(
        isOnline: true,
        lastHeartbeat: DateTime.now(),
      );
      notifyListeners();
    }
  }

  void _onAuthorizeRequest(Map<String, dynamic> d) {
    _authResultController.add(d);
    _addLog(ActivityLogEntry(
      type:    d['status'] == 'Accepted' ? LogType.authorize : LogType.error,
      cpId:    d['chargePointId'] ?? '',
      message: 'Authorize tag ${d['idTag']} → ${d['status']}',
    ));
    notifyListeners();
  }

  void _onTransactionStarted(Map<String, dynamic> d) {
    final tx = TransactionModel(
      transactionId:   (d['transactionId'] as num).toInt(),
      chargePointId:   d['chargePointId'] ?? '',
      connectorNumber: (d['connectorId'] as num?)?.toInt() ?? 1,
      idTag:           d['idTag'] ?? '',
      startTime:       DateTime.tryParse(d['startTime'] ?? '') ?? DateTime.now(),
      meterStart:      (d['meterStart'] as num?)?.toInt() ?? 0,
      status:          'Active',
    );
    _activeTransactions[tx.transactionId] = tx;

    _addLog(ActivityLogEntry(
      type:    LogType.transactionStart,
      cpId:    tx.chargePointId,
      message: 'Session started · tag ${tx.idTag} · connector ${tx.connectorNumber}',
      txId:    tx.transactionId,
    ));
    notifyListeners();
  }

  void _onTransactionStopped(Map<String, dynamic> d) {
    final txId = (d['transactionId'] as num).toInt();
    _activeTransactions.remove(txId);

    final energy = (d['energyDeliveredKwh'] as num?)?.toDouble() ?? 0;
    _addLog(ActivityLogEntry(
      type:    LogType.transactionStop,
      cpId:    d['chargePointId'] ?? '',
      message: 'Session ended · ${energy.toStringAsFixed(3)} kWh · ${d['reason'] ?? 'Normal'}',
      txId:    txId,
    ));
    notifyListeners();
  }

  void _onMeterValues(Map<String, dynamic> d) {
    final txId = (d['transactionId'] as num).toInt();
    final tx = _activeTransactions[txId];
    if (tx != null) {
      tx.liveEnergyWh  = (d['energyWh'] as num?)?.toDouble();
      tx.livePowerW    = (d['powerW'] as num?)?.toDouble();
      tx.liveVoltageV  = (d['voltageV'] as num?)?.toDouble();
      tx.liveCurrentA  = (d['currentA'] as num?)?.toDouble();
      tx.liveTimestamp = DateTime.tryParse(d['timestamp'] ?? '');

      // Keep last 30 power readings for the chart
      if (tx.livePowerW != null) {
        tx.powerHistory.add(tx.livePowerW! / 1000.0);
        if (tx.powerHistory.length > 30) tx.powerHistory.removeAt(0);
      }
      notifyListeners();
    }
  }

  void _onStatusUpdate(Map<String, dynamic> d) {
    final cpId = d['chargePointId'] as String? ?? '';
    final cp = _chargePoints[cpId];
    if (cp != null) {
      final connectors = (d['connectors'] as List<dynamic>? ?? [])
          .map((c) => ConnectorModel.fromJson(c as Map<String, dynamic>))
          .toList();
      _chargePoints[cpId] = cp.copyWith(
        isOnline:    d['isOnline'] ?? cp.isOnline,
        connectors:  connectors,
      );
      notifyListeners();
    }
  }

  void _onChargePointUpdated(Map<String, dynamic> d) {
    final cpId = d['chargePointId'] as String? ?? '';
    final cp = _chargePoints[cpId];
    if (cp != null) {
      _chargePoints[cpId] = cp.copyWith(
        vendor:          d['vendor']          as String?,
        model:           d['model']           as String?,
        serialNumber:    d['serialNumber']    as String?,
        firmwareVersion: d['firmwareVersion'] as String?,
      );
      _addLog(ActivityLogEntry(
        type:    LogType.command,
        cpId:    cpId,
        message: 'Charge point settings updated',
      ));
      notifyListeners();
    }
  }

  // ─── Remote Commands ──────────────────────────────────────────────────────

  Future<String?> remoteStart(String cpId, String idTag, int? connectorId) async {
    final result = await _hub.remoteStartTransaction(cpId, idTag, connectorId);
    final status = result?['status'] as String?;
    _addLog(ActivityLogEntry(
      type:    status == 'Accepted' ? LogType.command : LogType.error,
      cpId:    cpId,
      message: 'RemoteStart → tag $idTag connector $connectorId → ${status ?? 'no response'}',
    ));
    notifyListeners();
    return status;
  }

  Future<bool> remoteStop(String cpId, int transactionId) async {
    final result = await _hub.remoteStopTransaction(cpId, transactionId);
    _addLog(ActivityLogEntry(
      type:    LogType.command,
      cpId:    cpId,
      message: 'RemoteStop → txId $transactionId',
      txId:    transactionId,
    ));
    notifyListeners();
    return result != null;
  }

  Future<bool> changeAvailability(String cpId, int connectorId, String type) async {
    final result = await _hub.changeAvailability(cpId, connectorId, type);
    _addLog(ActivityLogEntry(
      type:    LogType.command,
      cpId:    cpId,
      message: 'ChangeAvailability → connector $connectorId → $type',
    ));
    notifyListeners();
    return result != null;
  }

  Future<bool> resetCp(String cpId, String type) async {
    final result = await _hub.resetChargePoint(cpId, type);
    _addLog(ActivityLogEntry(
      type:    LogType.command,
      cpId:    cpId,
      message: 'Reset ($type)',
    ));
    notifyListeners();
    return result != null;
  }

  Future<bool> unlockConnector(String cpId, int connectorId) async {
    final result = await _hub.unlockConnector(cpId, connectorId);
    _addLog(ActivityLogEntry(
      type: LogType.command, cpId: cpId,
      message: 'UnlockConnector → connector $connectorId',
    ));
    notifyListeners();
    return result != null;
  }

  Future<bool> clearCache(String cpId) async {
    final result = await _hub.clearCache(cpId);
    _addLog(ActivityLogEntry(type: LogType.command, cpId: cpId, message: 'ClearCache'));
    notifyListeners();
    return result != null;
  }

  Future<bool> triggerMessage(String cpId, String msg, int? connectorId) async {
    final result = await _hub.triggerMessage(cpId, msg, connectorId);
    _addLog(ActivityLogEntry(type: LogType.command, cpId: cpId, message: 'TriggerMessage → $msg'));
    notifyListeners();
    return result != null;
  }

  // ─── Tag Management ───────────────────────────────────────────────────────

  Future<void> refreshTags() async {
    _tags = await _api.getTags();
    notifyListeners();
  }

  Future<bool> createTag(String tagId, String? userName, String? note) async {
    final success = await _api.createTag(tagId: tagId, userName: userName, note: note);
    if (success) await refreshTags();
    return success;
  }

  Future<bool> blockTag(String tagId) async {
    final success = await _api.updateTagStatus(tagId, 'Blocked');
    if (success) await refreshTags();
    return success;
  }

  Future<bool> acceptTag(String tagId) async {
    final success = await _api.updateTagStatus(tagId, 'Accepted');
    if (success) await refreshTags();
    return success;
  }

  Future<bool> deleteTag(String tagId) async {
    final success = await _api.deleteTag(tagId);
    if (success) await refreshTags();
    return success;
  }

  // ─── Transaction history (REST) ───────────────────────────────────────────

  Future<Map<String, dynamic>> getTransactionHistory({
    String? cpId, String? idTag, String? status, int page = 1,
  }) async {
    return _api.getTransactions(cpId: cpId, idTag: idTag, status: status, page: page);
  }

  // ─── Dashboard stats computed from live state ─────────────────────────────

  DashboardStats get stats {
    final allConnectors = chargePoints.expand((cp) => cp.connectors).toList();
    return DashboardStats(
      totalChargePoints:   chargePoints.length,
      onlineChargePoints:  chargePoints.where((c) => c.isOnline).length,
      activeSessions:      activeTransactions.length,
      totalConnectors:     allConnectors.length,
      availableConnectors: allConnectors.where((c) => c.status == 'Available').length,
      chargingConnectors:  allConnectors.where((c) => c.status == 'Charging').length,
      faultedConnectors:   allConnectors.where((c) => c.status == 'Faulted').length,
    );
  }

  // ─── Activity log helpers ─────────────────────────────────────────────────

  void _addLog(ActivityLogEntry entry) {
    _activityLog.insert(0, entry);
    if (_activityLog.length > 100) _activityLog.removeLast();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _messageSub?.cancel();
    _authResultController.close();
    _hub.dispose();
    super.dispose();
  }
}

// ─── Activity Log Entry ───────────────────────────────────────────────────────

enum LogType { boot, offline, authorize, transactionStart, transactionStop, command, error }

class ActivityLogEntry {
  final LogType type;
  final String cpId;
  final String message;
  final int? txId;
  final DateTime timestamp;

  ActivityLogEntry({
    required this.type,
    required this.cpId,
    required this.message,
    this.txId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
