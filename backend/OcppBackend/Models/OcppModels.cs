// Models/OcppModels.cs
namespace OcppBackend.Models;

// ─── Enums ────────────────────────────────────────────────────────────────────

public enum ConnectorStatus
{
    Available,
    Preparing,
    Charging,
    SuspendedEVSE,
    SuspendedEV,
    Finishing,
    Reserved,
    Unavailable,
    Faulted
}

public enum ChargePointErrorCode
{
    NoError,
    ConnectorLockFailure,
    EVCommunicationError,
    GroundFailure,
    HighTemperature,
    InternalError,
    LocalListConflict,
    OtherError,
    OverCurrentFailure,
    PowerMeterFailure,
    PowerSwitchFailure,
    ReaderFailure,
    ResetFailure,
    UnderVoltage,
    OverVoltage,
    WeakSignal
}

public enum AuthorizationStatus
{
    Accepted,
    Blocked,
    Expired,
    Invalid,
    ConcurrentTx
}

public enum TransactionStatus
{
    Active,
    Completed,
    Invalid
}

public enum RegistrationStatus
{
    Accepted,
    Pending,
    Rejected
}

// ─── Database Entities ────────────────────────────────────────────────────────

public class ChargePoint
{
    public int Id { get; set; }
    public string ChargePointId { get; set; } = "";      // e.g. "CP-001"
    public string Vendor { get; set; } = "";
    public string Model { get; set; } = "";
    public string SerialNumber { get; set; } = "";
    public string FirmwareVersion { get; set; } = "";
    public bool IsOnline { get; set; }
    public DateTime? LastHeartbeat { get; set; }
    public DateTime? LastBootTime { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public ICollection<Connector> Connectors { get; set; } = new List<Connector>();
    public ICollection<Transaction> Transactions { get; set; } = new List<Transaction>();
}

public class Connector
{
    public int Id { get; set; }
    public int ChargePointId { get; set; }
    public int ConnectorId { get; set; }               // 1-based per OCPP spec
    public ConnectorStatus Status { get; set; } = ConnectorStatus.Unavailable;
    public ChargePointErrorCode ErrorCode { get; set; } = ChargePointErrorCode.NoError;
    public string? ErrorInfo { get; set; }
    public DateTime? StatusTimestamp { get; set; }

    [System.Text.Json.Serialization.JsonIgnore]
    public ChargePoint ChargePoint { get; set; } = null!;
    public ICollection<Transaction> Transactions { get; set; } = new List<Transaction>();
}

public class IdTag
{
    public int Id { get; set; }
    public string TagId { get; set; } = "";            // RFID tag string
    public string? UserId { get; set; }                // linked user (optional)
    public string? UserName { get; set; }
    public AuthorizationStatus Status { get; set; } = AuthorizationStatus.Accepted;
    public DateTime? ExpiryDate { get; set; }
    public string? ParentTagId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public string? Note { get; set; }
}

public class Transaction
{
    public int Id { get; set; }
    public int TransactionId { get; set; }             // OCPP transaction ID
    public int ChargePointId { get; set; }
    public int ConnectorId { get; set; }               // FK to Connector.Id
    public int ConnectorNumber { get; set; }           // 1-based connector number
    public string IdTag { get; set; } = "";
    public TransactionStatus Status { get; set; } = TransactionStatus.Active;
    public int MeterStart { get; set; }                // Wh
    public int? MeterStop { get; set; }                // Wh
    public DateTime StartTime { get; set; }
    public DateTime? StopTime { get; set; }
    public string? StopReason { get; set; }
    public double? EnergyDeliveredKwh { get; set; }

    [System.Text.Json.Serialization.JsonIgnore]
    public ChargePoint ChargePoint { get; set; } = null!;

    [System.Text.Json.Serialization.JsonIgnore]
    public Connector Connector { get; set; } = null!;
    public ICollection<MeterValue> MeterValues { get; set; } = new List<MeterValue>();
}

public class MeterValue
{
    public int Id { get; set; }
    public int TransactionId { get; set; }             // FK to Transaction.Id
    public DateTime Timestamp { get; set; }
    public double? EnergyWh { get; set; }
    public double? PowerW { get; set; }
    public double? VoltageV { get; set; }
    public double? CurrentA { get; set; }
    public string? Context { get; set; }               // "Sample.Periodic" etc.

    [System.Text.Json.Serialization.JsonIgnore]
    public Transaction Transaction { get; set; } = null!;
}

public class OcppMessageLog
{
    public int Id { get; set; }
    public string ChargePointId { get; set; } = "";
    public string Direction { get; set; } = "";        // "CP->CSMS" or "CSMS->CP"
    public string Action { get; set; } = "";
    public string MessageId { get; set; } = "";
    public string Payload { get; set; } = "";          // raw JSON
    public bool IsError { get; set; }
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
}

// ─── OCPP 1.6 Message Structures (used inside hub/service) ────────────────────

public record OcppBootNotificationRequest(
    string ChargePointVendor,
    string ChargePointModel,
    string? ChargePointSerialNumber,
    string? ChargeBoxSerialNumber,
    string? FirmwareVersion,
    string? Iccid,
    string? Imsi
);

public record OcppBootNotificationResponse(
    string Status,           // "Accepted" | "Pending" | "Rejected"
    string CurrentTime,
    int Interval
);

public record OcppHeartbeatResponse(string CurrentTime);

public record OcppIdTagInfo(
    string Status,
    string? ExpiryDate,
    string? ParentIdTag
);

public record OcppAuthorizeRequest(string IdTag);
public record OcppAuthorizeResponse(OcppIdTagInfo IdTagInfo);

public record OcppStartTransactionRequest(
    int ConnectorId,
    string IdTag,
    int MeterStart,
    string Timestamp,
    int? ReservationId
);

public record OcppStartTransactionResponse(
    int TransactionId,
    OcppIdTagInfo IdTagInfo
);

public record OcppStopTransactionRequest(
    int TransactionId,
    string? IdTag,
    int MeterStop,
    string Timestamp,
    string? Reason,
    List<object>? TransactionData
);

public record OcppStopTransactionResponse(OcppIdTagInfo? IdTagInfo);

public record OcppStatusNotificationRequest(
    int ConnectorId,
    string ErrorCode,
    string Status,
    string? Info,
    string? Timestamp,
    string? VendorId,
    string? VendorErrorCode
);

public record OcppMeterValuesRequest(
    int ConnectorId,
    int? TransactionId,
    List<OcppMeterValueEntry> MeterValue
);

public record OcppMeterValueEntry(
    string Timestamp,
    List<OcppSampledValue> SampledValue
);

public record OcppSampledValue(
    string Value,
    string? Context,
    string? Format,
    string? Measurand,
    string? Phase,
    string? Location,
    string? Unit
);

// ─── Remote Commands (CSMS → CP) ─────────────────────────────────────────────

public record RemoteStartTransactionRequest(string IdTag, int? ConnectorId, object? ChargingProfile);
public record RemoteStopTransactionRequest(int TransactionId);
public record ChangeAvailabilityRequest(int ConnectorId, string Type);  // "Operative"|"Inoperative"
public record ResetRequest(string Type);                                  // "Hard"|"Soft"
public record UnlockConnectorRequest(int ConnectorId);
public record GetConfigurationRequest(List<string>? Key);
public record ChangeConfigurationRequest(string Key, string Value);
public record TriggerMessageRequest(string RequestedMessage, int? ConnectorId);
public record ClearCacheRequest();

// ─── CSMS → App notification payloads (via SignalR to Flutter apps) ───────────

public record ChargePointStatusUpdate(
    string ChargePointId,
    bool IsOnline,
    DateTime? LastHeartbeat,
    IEnumerable<ConnectorStatusDto> Connectors
);

public record ConnectorStatusDto(
    int ConnectorId,
    string Status,
    string ErrorCode,
    int? ActiveTransactionId
);

public record TransactionStartedEvent(
    int TransactionId,
    string ChargePointId,
    int ConnectorId,
    string IdTag,
    DateTime StartTime,
    int MeterStart
);

public record TransactionUpdatedEvent(
    int TransactionId,
    double EnergyWh,
    double? PowerW,
    double? VoltageV,
    double? CurrentA,
    DateTime Timestamp
);

public record TransactionStoppedEvent(
    int TransactionId,
    string ChargePointId,
    int ConnectorId,
    string IdTag,
    DateTime StopTime,
    int MeterStop,
    double EnergyDeliveredKwh,
    string? Reason
);
