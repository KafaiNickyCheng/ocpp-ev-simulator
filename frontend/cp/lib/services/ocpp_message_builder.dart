// lib/services/ocpp_message_builder.dart
// Utility for building OCPP 1.6 JSON CALL frames and parsing CALLRESULT/CALLERROR.
//
// OCPP 1.6 frame formats:
//   CALL        [2, "msgId", "Action",  { payload }]
//   CALLRESULT  [3, "msgId",            { payload }]
//   CALLERROR   [4, "msgId", "errorCode", "description", {}]

import 'dart:convert';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

// ─── Frame Builders ───────────────────────────────────────────────────────────

/// Builds a CALL frame string ready to send.
String buildCall(String action, Map<String, dynamic> payload) {
  final msgId = _uuid.v4();
  final frame = [2, msgId, action, payload];
  return jsonEncode(frame);
}

/// Builds a CALLRESULT frame string (CP acknowledging a remote command).
String buildCallResult(String msgId, Map<String, dynamic> payload) {
  final frame = [3, msgId, payload];
  return jsonEncode(frame);
}

/// Builds a CALLERROR frame string.
String buildCallError(String msgId, String errorCode, String description) {
  final frame = [4, msgId, errorCode, description, <String, dynamic>{}];
  return jsonEncode(frame);
}

// ─── Frame Parser ─────────────────────────────────────────────────────────────

class OcppFrame {
  final int messageType;   // 2=CALL, 3=CALLRESULT, 4=CALLERROR
  final String messageId;
  final String? action;    // only on CALL
  final Map<String, dynamic> payload;
  final String? errorCode;

  OcppFrame({
    required this.messageType,
    required this.messageId,
    this.action,
    required this.payload,
    this.errorCode,
  });

  bool get isCall       => messageType == 2;
  bool get isResult     => messageType == 3;
  bool get isError      => messageType == 4;
}

OcppFrame? parseFrame(String raw) {
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    final msgType = list[0] as int;
    final msgId   = list[1] as String;

    if (msgType == 2) {
      // CALL: [2, msgId, action, payload]
      final action  = list[2] as String;
      final payload = list.length > 3 ? Map<String, dynamic>.from(list[3] as Map) : <String, dynamic>{};
      return OcppFrame(messageType: 2, messageId: msgId, action: action, payload: payload);
    } else if (msgType == 3) {
      // CALLRESULT: [3, msgId, payload]
      final payload = list.length > 2 ? Map<String, dynamic>.from(list[2] as Map) : <String, dynamic>{};
      return OcppFrame(messageType: 3, messageId: msgId, payload: payload);
    } else if (msgType == 4) {
      // CALLERROR: [4, msgId, errorCode, description, {}]
      final errorCode = list[2] as String;
      return OcppFrame(messageType: 4, messageId: msgId, payload: {}, errorCode: errorCode);
    }
  } catch (e) {
    return null;
  }
  return null;
}

// ─── Specific CALL frame builders ─────────────────────────────────────────────

String buildBootNotification({
  required String vendor,
  required String model,
  required String serialNumber,
  required String firmwareVersion,
}) {
  return buildCall('BootNotification', {
    'chargePointVendor':       vendor,
    'chargePointModel':        model,
    'chargePointSerialNumber': serialNumber,
    'firmwareVersion':         firmwareVersion,
  });
}

String buildHeartbeat() => buildCall('Heartbeat', {});

String buildAuthorize(String idTag) =>
    buildCall('Authorize', {'idTag': idTag});

String buildStatusNotification({
  required int connectorId,
  required String status,
  required String errorCode,
  String? info,
}) {
  return buildCall('StatusNotification', {
    'connectorId': connectorId,
    'errorCode':   errorCode,
    'status':      status,
    if (info != null) 'info': info,
    'timestamp':   DateTime.now().toUtc().toIso8601String(),
  });
}

String buildStartTransaction({
  required int connectorId,
  required String idTag,
  required int meterStart,
}) {
  return buildCall('StartTransaction', {
    'connectorId': connectorId,
    'idTag':       idTag,
    'meterStart':  meterStart,
    'timestamp':   DateTime.now().toUtc().toIso8601String(),
  });
}

String buildStopTransaction({
  required int transactionId,
  required String idTag,
  required int meterStop,
  String reason = 'Local',
}) {
  return buildCall('StopTransaction', {
    'transactionId': transactionId,
    'idTag':         idTag,
    'meterStop':     meterStop,
    'timestamp':     DateTime.now().toUtc().toIso8601String(),
    'reason':        reason,
  });
}

String buildMeterValues({
  required int connectorId,
  required int transactionId,
  required double energyWh,
  required double powerW,
  required double voltageV,
  required double currentA,
}) {
  return buildCall('MeterValues', {
    'connectorId':   connectorId,
    'transactionId': transactionId,
    'meterValue': [
      {
        'timestamp':    DateTime.now().toUtc().toIso8601String(),
        'sampledValue': [
          {
            'value':     energyWh.toStringAsFixed(1),
            'measurand': 'Energy.Active.Import.Register',
            'unit':      'Wh',
            'context':   'Sample.Periodic',
          },
          {
            'value':     powerW.toStringAsFixed(1),
            'measurand': 'Power.Active.Import',
            'unit':      'W',
            'context':   'Sample.Periodic',
          },
          {
            'value':     voltageV.toStringAsFixed(1),
            'measurand': 'Voltage',
            'unit':      'V',
            'context':   'Sample.Periodic',
          },
          {
            'value':     currentA.toStringAsFixed(2),
            'measurand': 'Current.Import',
            'unit':      'A',
            'context':   'Sample.Periodic',
          },
        ],
      }
    ],
  });
}
