// lib/models/cp_models.dart
// Data models for the ChargePoint simulator app.

// ─── Enums ────────────────────────────────────────────────────────────────────

enum CpConnectionState { disconnected, connecting, connected, reconnecting }

enum ConnectorStatus {
  Available,
  Preparing,
  Charging,
  SuspendedEVSE,
  SuspendedEV,
  Finishing,
  Reserved,
  Unavailable,
  Faulted,
}

enum SimulatorPhase {
  idle,        // No session — connector is Available
  preparing,   // Card presented, waiting for StartTransaction
  charging,    // Transaction active, meter ticking
  finishing,   // StopTransaction sent, wrapping up
}

// ─── Connector State ──────────────────────────────────────────────────────────

class ConnectorState {
  final int connectorId;
  final ConnectorStatus status;
  final SimulatorPhase phase;
  final int? activeTransactionId;
  final String? activeIdTag;
  final DateTime? sessionStartTime;
  final int meterStartWh;
  final int currentMeterWh;      // live meter reading
  final double? powerW;
  final double? voltageV;
  final double? currentA;
  final List<double> powerHistory; // last 30 readings for chart

  const ConnectorState({
    required this.connectorId,
    this.status = ConnectorStatus.Unavailable,
    this.phase = SimulatorPhase.idle,
    this.activeTransactionId,
    this.activeIdTag,
    this.sessionStartTime,
    this.meterStartWh = 0,
    this.currentMeterWh = 0,
    this.powerW,
    this.voltageV,
    this.currentA,
    this.powerHistory = const [],
  });

  bool get isCharging    => phase == SimulatorPhase.charging;
  bool get isIdle        => phase == SimulatorPhase.idle;
  bool get hasSession    => activeTransactionId != null;

  Duration get sessionDuration =>
      sessionStartTime != null ? DateTime.now().difference(sessionStartTime!) : Duration.zero;

  double get energyDeliveredKwh => (currentMeterWh - meterStartWh) / 1000.0;

  ConnectorState copyWith({
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
    return ConnectorState(
      connectorId:          connectorId,
      status:               status ?? this.status,
      phase:                phase ?? this.phase,
      activeTransactionId:  clearTransaction ? null : (activeTransactionId ?? this.activeTransactionId),
      activeIdTag:          clearTransaction ? null : (activeIdTag ?? this.activeIdTag),
      sessionStartTime:     clearSession ? null : (sessionStartTime ?? this.sessionStartTime),
      meterStartWh:         meterStartWh ?? this.meterStartWh,
      currentMeterWh:       currentMeterWh ?? this.currentMeterWh,
      powerW:               powerW ?? this.powerW,
      voltageV:             voltageV ?? this.voltageV,
      currentA:             currentA ?? this.currentA,
      powerHistory:         powerHistory ?? this.powerHistory,
    );
  }
}

// ─── CP Settings (persisted) ──────────────────────────────────────────────────

class CpSettings {
  final String serverUrl;
  final String chargePointId;
  final String vendor;
  final String model;
  final String serialNumber;
  final String firmwareVersion;
  final int connectorCount;
  final int heartbeatIntervalSec;
  final int meterValueIntervalSec;
  final double simulatedMaxPowerKw; // max power to simulate per connector

  const CpSettings({
    this.serverUrl           = 'https://ocpp-ev-api.up.railway.app',
    this.chargePointId       = 'CP-SIM-001',
    this.vendor              = 'SimCo',
    this.model               = 'SimStation',
    this.serialNumber        = 'SN-0001',
    this.firmwareVersion     = '1.0.0',
    this.connectorCount      = 2,
    this.heartbeatIntervalSec  = 30,
    this.meterValueIntervalSec = 15,
    this.simulatedMaxPowerKw   = 22.0,
  });

  CpSettings copyWith({
    String? serverUrl,
    String? chargePointId,
    String? vendor,
    String? model,
    String? serialNumber,
    String? firmwareVersion,
    int? connectorCount,
    int? heartbeatIntervalSec,
    int? meterValueIntervalSec,
    double? simulatedMaxPowerKw,
  }) {
    return CpSettings(
      serverUrl:              serverUrl ?? this.serverUrl,
      chargePointId:          chargePointId ?? this.chargePointId,
      vendor:                 vendor ?? this.vendor,
      model:                  model ?? this.model,
      serialNumber:           serialNumber ?? this.serialNumber,
      firmwareVersion:        firmwareVersion ?? this.firmwareVersion,
      connectorCount:         connectorCount ?? this.connectorCount,
      heartbeatIntervalSec:   heartbeatIntervalSec ?? this.heartbeatIntervalSec,
      meterValueIntervalSec:  meterValueIntervalSec ?? this.meterValueIntervalSec,
      simulatedMaxPowerKw:    simulatedMaxPowerKw ?? this.simulatedMaxPowerKw,
    );
  }
}

// ─── OCPP Message Log ─────────────────────────────────────────────────────────

enum OcppDirection { sent, received }

class OcppLogEntry {
  final OcppDirection direction;
  final String action;
  final String payload;
  final bool isError;
  final DateTime timestamp;

  OcppLogEntry({
    required this.direction,
    required this.action,
    required this.payload,
    this.isError = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isSent => direction == OcppDirection.sent;
}
