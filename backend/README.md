# OCPP 1.6 Backend — C# .NET 8 + SQLite + SignalR

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                         OCPP Backend                             │
│                                                                  │
│  ┌─────────────┐   SignalR /ocpp    ┌──────────────────────┐    │
│  │ Charge Point│◄──────────────────►│     OcppHub.cs        │    │
│  │  (Flutter)  │   OCPP 1.6 JSON   │  (WebSocket / SignalR)│    │
│  └─────────────┘                   └──────────┬───────────┘    │
│                                               │                  │
│  ┌─────────────┐   SignalR /ocpp              │                  │
│  │  CSMS App   │◄─────────────────────────────┤                  │
│  │  (Flutter)  │   Push notifications         │                  │
│  └─────────────┘   Remote commands            │                  │
│                                               │                  │
│  ┌─────────────┐   SignalR /ocpp              │                  │
│  │  Client App │◄─────────────────────────────┤                  │
│  │  (Flutter)  │   Charging updates           │                  │
│  └─────────────┘                         ┌───▼──────────┐       │
│                                          │  AppDbContext │       │
│  ┌─────────────┐   REST /api             │  (SQLite EF) │       │
│  │  Any Client │◄────────────────────────┤              │       │
│  │  (Swagger)  │   CRUD for tags/logs    └──────────────┘       │
│  └─────────────┘                                                 │
└──────────────────────────────────────────────────────────────────┘
```

## Setup & Run

### Prerequisites
- .NET 8 SDK: https://dotnet.microsoft.com/download/dotnet/8.0

### First Run
```bash
cd OcppBackend

# Restore packages
dotnet restore

# Apply migrations (creates ocpp.db automatically)
dotnet ef database update

# Run
dotnet run
```

The server starts on:
- **SignalR Hub**: `ws://localhost:5000/ocpp`
- **REST API**: `http://localhost:5000/api`
- **Swagger UI**: `http://localhost:5000/swagger`

---

## SignalR Hub — `/ocpp`

### Connecting (query parameters)

All clients connect to `ws://localhost:5000/ocpp` with query params:

| Client Type | Query Params | Group Joined |
|---|---|---|
| Charge Point | `?clientType=cp&cpId=CP-001` | `CP:CP-001` |
| CSMS App | `?clientType=csms` | `csms` |
| End-User App | `?clientType=client&idTag=TAG-001` | `client:TAG-001` |

---

### CP → Backend: `OcppMessage(string rawFrame)`

The Charge Point sends raw OCPP 1.6 JSON frames and receives a CallResult back.

**CALL Frame format:**
```json
[2, "msgId", "Action", { ...payload }]
```

**CallResult Frame format (returned):**
```json
[3, "msgId", { ...responsePayload }]
```

#### Supported Actions (CP → CSMS)

| Action | Request Payload | Response Payload |
|---|---|---|
| `BootNotification` | `chargePointVendor`, `chargePointModel`, `chargePointSerialNumber`, `firmwareVersion` | `{ status, currentTime, interval }` |
| `Heartbeat` | `{}` | `{ currentTime }` |
| `Authorize` | `{ idTag }` | `{ idTagInfo: { status, expiryDate } }` |
| `StartTransaction` | `{ connectorId, idTag, meterStart, timestamp }` | `{ transactionId, idTagInfo }` |
| `StopTransaction` | `{ transactionId, idTag, meterStop, timestamp, reason }` | `{ idTagInfo }` |
| `StatusNotification` | `{ connectorId, errorCode, status, timestamp }` | `{}` |
| `MeterValues` | `{ connectorId, transactionId, meterValue: [...] }` | `{}` |
| `DataTransfer` | `{ vendorId, messageId, data }` | `{ status }` |
| `DiagnosticsStatusNotification` | `{ status }` | `{}` |
| `FirmwareStatusNotification` | `{ status }` | `{}` |

---

### CSMS App → Backend: Remote Commands

The CSMS Flutter app calls these SignalR methods directly:

| Method | Parameters | Description |
|---|---|---|
| `SendRemoteStartTransaction` | `cpId, idTag, connectorId?` | Start a session remotely |
| `SendRemoteStopTransaction` | `cpId, transactionId` | Stop a session remotely |
| `SendChangeAvailability` | `cpId, connectorId, type` | `"Operative"` or `"Inoperative"` |
| `SendReset` | `cpId, type` | `"Soft"` or `"Hard"` |
| `SendUnlockConnector` | `cpId, connectorId` | Unlock connector |
| `SendGetConfiguration` | `cpId, keys?` | Get CP config keys |
| `SendChangeConfiguration` | `cpId, key, value` | Change CP config |
| `SendTriggerMessage` | `cpId, requestedMessage, connectorId?` | Trigger a message |
| `SendClearCache` | `cpId` | Clear CP local cache |
| `GetAllChargePoints` | — | Returns all CP statuses |
| `GetActiveTransactions` | — | Returns all active transactions |

---

### Backend → CSMS App: Push Events

Received by the CSMS app via `connection.on("EventName", handler)`:

| Event | Payload | Trigger |
|---|---|---|
| `ChargePointBooted` | `{ chargePointId, vendor, model, ... }` | BootNotification received |
| `ChargePointOffline` | `{ chargePointId, timestamp }` | CP disconnected |
| `HeartbeatReceived` | `{ chargePointId, timestamp }` | Heartbeat received |
| `AuthorizeRequest` | `{ chargePointId, idTag, status }` | Authorize received |
| `TransactionStarted` | `{ transactionId, chargePointId, connectorId, idTag, startTime, meterStart }` | StartTransaction accepted |
| `TransactionStopped` | `{ transactionId, chargePointId, connectorId, idTag, stopTime, meterStop, energyDeliveredKwh, reason }` | StopTransaction received |
| `MeterValuesUpdated` | `{ transactionId, energyWh, powerW, voltageV, currentA, timestamp }` | MeterValues received |
| `ChargePointStatusUpdate` | `{ chargePointId, isOnline, lastHeartbeat, connectors: [...] }` | StatusNotification received |

---

### Backend → Client App: Push Events

Received by the end-user app via `connection.on("EventName", handler)`:

| Event | Payload | Trigger |
|---|---|---|
| `TransactionStarted` | Same as above | Their session started |
| `TransactionStopped` | Same as above | Their session ended |
| `ChargingUpdate` | `{ transactionId, energyWh, powerW, voltageV, currentA, timestamp }` | Meter value update |

#### Client Query Methods

| Method | Parameters | Returns |
|---|---|---|
| `GetMyTransactions` | `idTag` | Last 20 transactions for this tag |
| `GetActiveTransactionForTag` | `idTag` | Current active session (if any) |

---

## REST API — `/api`

| Method | Endpoint | Description |
|---|---|---|
| GET | `/api/health` | Health check |
| GET | `/api/chargepoints` | All charge points + connectors |
| GET | `/api/chargepoints/{cpId}` | Single CP |
| GET | `/api/transactions?cpId=&idTag=&status=&page=&pageSize=` | Paginated transactions |
| GET | `/api/transactions/{txId}` | Transaction + meter values |
| GET | `/api/tags` | All ID tags |
| GET | `/api/tags/{tagId}` | Single tag |
| POST | `/api/tags` | Register new tag |
| PUT | `/api/tags/{tagId}` | Update tag (status/expiry) |
| DELETE | `/api/tags/{tagId}` | Delete tag |
| GET | `/api/logs?cpId=&page=&pageSize=` | OCPP message logs |

---

## Database Schema (SQLite — `ocpp.db`)

```
ChargePoints    → stores each unique CP (auto-created on BootNotification)
Connectors      → one row per connector per CP (auto-created on StatusNotification)
IdTags          → registered RFID/NFC tags + authorization status
Transactions    → one row per charging session
MeterValues     → periodic meter samples per transaction
MessageLogs     → raw OCPP frame log (capped at 4000 chars payload)
```

---

## Flutter Integration Guide

### Install SignalR package
```yaml
# pubspec.yaml
dependencies:
  signalr_netcore: ^1.3.4
```

### Charge Point Connection
```dart
final hub = HubConnectionBuilder()
  .withUrl("http://localhost:5000/ocpp?clientType=cp&cpId=CP-001")
  .withAutomaticReconnect()
  .build();

await hub.start();

// Send OCPP message
final frame = jsonEncode([2, msgId, "BootNotification", payload]);
final result = await hub.invoke("OcppMessage", args: [frame]);
// result is the CallResult JSON string [3, msgId, {...}]

// Listen for remote commands from CSMS
hub.on("OcppCommand", (args) {
  final frame = jsonDecode(args![0]);
  // frame is [2, msgId, action, payload]
  // handle it, then send back CallResult via OcppMessage
});
```

### CSMS App Connection
```dart
final hub = HubConnectionBuilder()
  .withUrl("http://localhost:5000/ocpp?clientType=csms")
  .withAutomaticReconnect()
  .build();

await hub.start();

// Listen for events
hub.on("TransactionStarted", (args) { ... });
hub.on("ChargePointStatusUpdate", (args) { ... });
hub.on("MeterValuesUpdated", (args) { ... });

// Send remote command
await hub.invoke("SendRemoteStartTransaction", args: ["CP-001", "TAG-001", 1]);
```

### Client App Connection
```dart
final hub = HubConnectionBuilder()
  .withUrl("http://localhost:5000/ocpp?clientType=client&idTag=TAG-001")
  .withAutomaticReconnect()
  .build();

await hub.start();

hub.on("ChargingUpdate", (args) { /* real-time power/energy updates */ });
hub.on("TransactionStopped", (args) { /* session ended */ });

// Query active session
final result = await hub.invoke("GetActiveTransactionForTag", args: ["TAG-001"]);
```

---

## OCPP 1.6 Compliance Notes

- All message types: CALL (2), CALLRESULT (3), CALLERROR (4) ✓
- Authorization via local IdTag table (whitelist/blacklist) ✓
- Transaction IDs are globally unique, persisted ✓
- MeterValues: Energy, Power, Voltage, Current measurands ✓
- StatusNotification persists connector state ✓
- Heartbeat updates `lastHeartbeat`, marks CP online ✓
- Disconnect marks CP offline, notifies CSMS ✓
- Remote commands: RemoteStart/Stop, Reset, ChangeAvailability, UnlockConnector, GetConfiguration, ChangeConfiguration, TriggerMessage, ClearCache ✓
