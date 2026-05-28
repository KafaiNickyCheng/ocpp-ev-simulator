// lib/models/csms_models.dart
// Data models used throughout the CSMS app.
// These mirror the JSON payloads sent by the backend SignalR hub.

// ─── Charge Point ─────────────────────────────────────────────────────────────

class ChargePointModel {
  final String chargePointId;
  final String vendor;
  final String model;
  final String serialNumber;
  final String firmwareVersion;
  final bool isOnline;
  final DateTime? lastHeartbeat;
  final DateTime? lastBootTime;
  final List<ConnectorModel> connectors;

  ChargePointModel({
    required this.chargePointId,
    required this.vendor,
    required this.model,
    required this.serialNumber,
    required this.firmwareVersion,
    required this.isOnline,
    this.lastHeartbeat,
    this.lastBootTime,
    required this.connectors,
  });

  factory ChargePointModel.fromJson(Map<String, dynamic> json) {
    return ChargePointModel(
      chargePointId:   json['chargePointId'] ?? '',
      vendor:          json['vendor'] ?? '',
      model:           json['model'] ?? '',
      serialNumber:    json['serialNumber'] ?? '',
      firmwareVersion: json['firmwareVersion'] ?? '',
      isOnline:        json['isOnline'] ?? false,
      lastHeartbeat:   json['lastHeartbeat'] != null
          ? DateTime.tryParse(json['lastHeartbeat'])
          : null,
      lastBootTime:    json['lastBootTime'] != null
          ? DateTime.tryParse(json['lastBootTime'])
          : null,
      connectors: (json['connectors'] as List<dynamic>? ?? [])
          .map((c) => ConnectorModel.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  ChargePointModel copyWith({
    String? vendor,
    String? model,
    String? serialNumber,
    String? firmwareVersion,
    bool? isOnline,
    DateTime? lastHeartbeat,
    DateTime? lastBootTime,
    List<ConnectorModel>? connectors,
  }) {
    return ChargePointModel(
      chargePointId:   chargePointId,
      vendor:          vendor          ?? this.vendor,
      model:           model           ?? this.model,
      serialNumber:    serialNumber    ?? this.serialNumber,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      isOnline:        isOnline        ?? this.isOnline,
      lastHeartbeat:   lastHeartbeat   ?? this.lastHeartbeat,
      lastBootTime:    lastBootTime    ?? this.lastBootTime,
      connectors:      connectors      ?? this.connectors,
    );
  }
}

// ─── Connector ────────────────────────────────────────────────────────────────

class ConnectorModel {
  final int connectorId;
  final String status;      // Available, Charging, Preparing, Faulted, etc.
  final String errorCode;
  final int? activeTransactionId;
  final DateTime? statusTimestamp;

  ConnectorModel({
    required this.connectorId,
    required this.status,
    required this.errorCode,
    this.activeTransactionId,
    this.statusTimestamp,
  });

  factory ConnectorModel.fromJson(Map<String, dynamic> json) {
    return ConnectorModel(
      connectorId:         json['connectorId'] ?? 0,
      status:              json['status'] ?? 'Unavailable',
      errorCode:           json['errorCode'] ?? 'NoError',
      activeTransactionId: json['activeTransactionId'],
      statusTimestamp:     json['statusTimestamp'] != null
          ? DateTime.tryParse(json['statusTimestamp'])
          : null,
    );
  }

  bool get isCharging       => status == 'Charging';
  bool get isAvailable      => status == 'Available';
  bool get isFaulted        => status == 'Faulted';
  bool get hasActiveSession => activeTransactionId != null;
}

// ─── Transaction ──────────────────────────────────────────────────────────────

class TransactionModel {
  final int transactionId;
  final String chargePointId;
  final int connectorNumber;
  final String idTag;
  final DateTime startTime;
  final DateTime? stopTime;
  final int meterStart;
  final int? meterStop;
  final double? energyDeliveredKwh;
  final String status;      // Active, Completed, Invalid
  final String? stopReason;

  // Live values — updated via MeterValues push
  double? liveEnergyWh;
  double? livePowerW;
  double? liveVoltageV;
  double? liveCurrentA;
  DateTime? liveTimestamp;

  // Power history for chart
  final List<double> powerHistory;

  TransactionModel({
    required this.transactionId,
    required this.chargePointId,
    required this.connectorNumber,
    required this.idTag,
    required this.startTime,
    this.stopTime,
    required this.meterStart,
    this.meterStop,
    this.energyDeliveredKwh,
    required this.status,
    this.stopReason,
    this.liveEnergyWh,
    this.livePowerW,
    this.liveVoltageV,
    this.liveCurrentA,
    this.liveTimestamp,
    List<double>? powerHistory,
  }) : powerHistory = powerHistory ?? [];

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      transactionId:      json['transactionId'] ?? 0,
      chargePointId:      json['chargePointId'] ?? '',
      connectorNumber:    json['connectorNumber'] ?? 0,
      idTag:              json['idTag'] ?? '',
      startTime:          DateTime.tryParse(json['startTime'] ?? '') ?? DateTime.now(),
      stopTime:           json['stopTime'] != null ? DateTime.tryParse(json['stopTime']) : null,
      meterStart:         json['meterStart'] ?? 0,
      meterStop:          json['meterStop'],
      energyDeliveredKwh: (json['energyDeliveredKwh'] as num?)?.toDouble(),
      status:             json['status'] ?? 'Active',
      stopReason:         json['stopReason'],
    );
  }

  bool get isActive    => status == 'Active';
  Duration get elapsed => DateTime.now().difference(startTime);

  double get energyKwh {
    if (liveEnergyWh != null) return liveEnergyWh! / 1000.0;
    if (energyDeliveredKwh != null) return energyDeliveredKwh!;
    return 0;
  }

  double get powerKw => (livePowerW ?? 0) / 1000.0;
}

// ─── RFID / ID Tag ────────────────────────────────────────────────────────────

class IdTagModel {
  final int id;
  final String tagId;
  final String? userName;
  final String? userId;
  final String status;       // Accepted, Blocked, Expired, Invalid
  final DateTime? expiryDate;
  final DateTime createdAt;
  final String? note;

  IdTagModel({
    required this.id,
    required this.tagId,
    this.userName,
    this.userId,
    required this.status,
    this.expiryDate,
    required this.createdAt,
    this.note,
  });

  factory IdTagModel.fromJson(Map<String, dynamic> json) {
    return IdTagModel(
      id:         (json['id'] as num?)?.toInt() ?? 0,
      tagId:      json['tagId']?.toString() ?? '',
      userName:   json['userName']?.toString(),
      userId:     json['userId']?.toString(),
      status:     json['status']?.toString() ?? 'Accepted',
      expiryDate: json['expiryDate'] != null ? DateTime.tryParse(json['expiryDate'].toString()) : null,
      createdAt:  DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      note:       json['note']?.toString(),
    );
  }

  bool get isAccepted => status == 'Accepted';
  bool get isBlocked  => status == 'Blocked';
  bool get isExpired  => expiryDate != null && expiryDate!.isBefore(DateTime.now());
}

// ─── OCPP Message Log ─────────────────────────────────────────────────────────

class MessageLogModel {
  final int id;
  final String chargePointId;
  final String direction;  // "CP->CSMS" or "CSMS->CP"
  final String action;
  final String messageId;
  final String payload;
  final bool isError;
  final DateTime timestamp;

  MessageLogModel({
    required this.id,
    required this.chargePointId,
    required this.direction,
    required this.action,
    required this.messageId,
    required this.payload,
    required this.isError,
    required this.timestamp,
  });

  factory MessageLogModel.fromJson(Map<String, dynamic> json) {
    return MessageLogModel(
      id:            json['id'] ?? 0,
      chargePointId: json['chargePointId'] ?? '',
      direction:     json['direction'] ?? '',
      action:        json['action'] ?? '',
      messageId:     json['messageId'] ?? '',
      payload:       json['payload'] ?? '',
      isError:       json['isError'] ?? false,
      timestamp:     DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
    );
  }

  bool get isOutbound => direction == 'CSMS->CP';
}

// ─── Summary stats (for dashboard) ───────────────────────────────────────────

class DashboardStats {
  final int totalChargePoints;
  final int onlineChargePoints;
  final int activeSessions;
  final int totalConnectors;
  final int availableConnectors;
  final int chargingConnectors;
  final int faultedConnectors;

  const DashboardStats({
    this.totalChargePoints   = 0,
    this.onlineChargePoints  = 0,
    this.activeSessions      = 0,
    this.totalConnectors     = 0,
    this.availableConnectors = 0,
    this.chargingConnectors  = 0,
    this.faultedConnectors   = 0,
  });
}