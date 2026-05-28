// lib/models/ocpp_models.dart

enum OcppVersion { ocpp16, ocpp201 }

enum ChargePointStatus {
  available,
  preparing,
  charging,
  suspendedEVSE,
  suspendedEV,
  finishing,
  reserved,
  unavailable,
  faulted,
}

enum ConnectorStatus {
  available,
  occupied,
  reserved,
  unavailable,
  faulted,
}

enum AuthorizationStatus {
  accepted,
  blocked,
  expired,
  invalid,
  concurrentTx,
}

enum TransactionStatus { idle, authorized, charging, stopping }

enum OcppMessageType { call, callResult, callError }

enum ChargePointErrorCode {
  connectorLockFailure,
  evCommunicationError,
  groundFailure,
  highTemperature,
  internalError,
  localListConflict,
  noError,
  otherError,
  overCurrentFailure,
  powerMeterFailure,
  powerSwitchFailure,
  readerFailure,
  resetFailure,
  underVoltage,
  overVoltage,
  weakSignal,
}

// ─── OCPP Message Envelope ───────────────────────────────────────────────────

class OcppMessage {
  final OcppMessageType type;
  final String messageId;
  final String? action;       // only for CALL
  final dynamic payload;
  final String? errorCode;    // only for CALLERROR
  final String? errorDescription;

  const OcppMessage({
    required this.type,
    required this.messageId,
    this.action,
    this.payload,
    this.errorCode,
    this.errorDescription,
  });

  List<dynamic> toJson() {
    switch (type) {
      case OcppMessageType.call:
        return [2, messageId, action, payload ?? {}];
      case OcppMessageType.callResult:
        return [3, messageId, payload ?? {}];
      case OcppMessageType.callError:
        return [4, messageId, errorCode ?? 'GenericError', errorDescription ?? '', {}];
    }
  }
}

// ─── Connector Model ─────────────────────────────────────────────────────────

class ConnectorModel {
  final int id;
  ConnectorStatus status;
  double currentPowerKw;
  double energyDeliveredKwh;
  String? activeTransactionId;
  String? authorizedIdTag;
  DateTime? sessionStart;
  List<MeterSample> meterHistory;

  ConnectorModel({
    required this.id,
    this.status = ConnectorStatus.available,
    this.currentPowerKw = 0,
    this.energyDeliveredKwh = 0,
    this.activeTransactionId,
    this.authorizedIdTag,
    this.sessionStart,
    List<MeterSample>? meterHistory,
  }) : meterHistory = meterHistory ?? [];

  Duration get sessionDuration =>
      sessionStart != null ? DateTime.now().difference(sessionStart!) : Duration.zero;

  double get sessionCostEstimate => energyDeliveredKwh * 0.30; // $0.30/kWh mock

  ConnectorModel copyWith({
    ConnectorStatus? status,
    double? currentPowerKw,
    double? energyDeliveredKwh,
    String? activeTransactionId,
    String? authorizedIdTag,
    DateTime? sessionStart,
    List<MeterSample>? meterHistory,
  }) {
    return ConnectorModel(
      id: id,
      status: status ?? this.status,
      currentPowerKw: currentPowerKw ?? this.currentPowerKw,
      energyDeliveredKwh: energyDeliveredKwh ?? this.energyDeliveredKwh,
      activeTransactionId: activeTransactionId ?? this.activeTransactionId,
      authorizedIdTag: authorizedIdTag ?? this.authorizedIdTag,
      sessionStart: sessionStart ?? this.sessionStart,
      meterHistory: meterHistory ?? this.meterHistory,
    );
  }
}

// ─── Meter Value Sample ───────────────────────────────────────────────────────

class MeterSample {
  final DateTime timestamp;
  final double powerKw;
  final double energyKwh;
  final double voltage;
  final double currentA;

  const MeterSample({
    required this.timestamp,
    required this.powerKw,
    required this.energyKwh,
    required this.voltage,
    required this.currentA,
  });
}

// ─── Charge Point Configuration ──────────────────────────────────────────────

class ChargePointConfig {
  String chargePointId;
  String centralSystemUrl;
  OcppVersion ocppVersion;
  int numberOfConnectors;
  String vendor;
  String model;
  String serialNumber;
  String firmwareVersion;
  int heartbeatInterval;       // seconds
  int meterValueInterval;      // seconds
  double maxPowerKw;

  ChargePointConfig({
    this.chargePointId = 'CP-SIMULATOR-001',
    this.centralSystemUrl = 'ws://localhost:9000/CP-SIMULATOR-001',
    this.ocppVersion = OcppVersion.ocpp16,
    this.numberOfConnectors = 2,
    this.vendor = 'SimCo',
    this.model = 'SimCharger X1',
    this.serialNumber = 'SIM-2024-00001',
    this.firmwareVersion = '1.0.0',
    this.heartbeatInterval = 30,
    this.meterValueInterval = 15,
    this.maxPowerKw = 22.0,
  });
}

// ─── Log Entry ────────────────────────────────────────────────────────────────

enum LogDirection { sent, received, system }

class LogEntry {
  final DateTime timestamp;
  final LogDirection direction;
  final String message;
  final String? rawData;
  final bool isError;

  const LogEntry({
    required this.timestamp,
    required this.direction,
    required this.message,
    this.rawData,
    this.isError = false,
  });
}

// ─── Connection State ─────────────────────────────────────────────────────────

enum CpConnectionState { disconnected, connecting, connected, reconnecting }