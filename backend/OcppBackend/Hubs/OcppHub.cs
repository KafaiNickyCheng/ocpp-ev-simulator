using System.Text.Json;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using OcppBackend.Data;
using OcppBackend.Models;
using OcppBackend.Services;

namespace OcppBackend.Hubs;

public class OcppHub : Hub
{
    private readonly AppDbContext _db;
    private readonly TransactionIdService _txIdService;
    private readonly ILogger<OcppHub> _logger;

    // ─── In-memory connection registry ───────────────────────────────────────
    // Maps SignalR ConnectionId → ChargePointId so we know which CP sent a message.
    // Static so it persists across hub instances (SignalR creates a new hub
    // instance per method call). Protected with a lock for thread safety.
    private static readonly Dictionary<string, string> _cpConnections = new();
    private static readonly object _cpLock = new();

    // JSON options: camelCase output (OCPP spec uses camelCase), case-insensitive input
    private static readonly JsonSerializerOptions _jsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
    };

    public OcppHub(AppDbContext db, TransactionIdService txIdService, ILogger<OcppHub> logger)
    {
        _db = db;
        _txIdService = txIdService;
        _logger = logger;
    }

    // =========================================================================
    // CONNECTION LIFECYCLE
    // =========================================================================

    /// <summary>
    /// Called automatically by SignalR when any client connects.
    /// We read the ?clientType query param to decide which group to join.
    ///
    /// Connection URLs:
    ///   CP:     ws://host/ocpp?clientType=cp&cpId=CP-001
    ///   CSMS:   ws://host/ocpp?clientType=csms
    ///   Client: ws://host/ocpp?clientType=client&idTag=TAG-001
    /// </summary>
    public override async Task OnConnectedAsync()
    {
        var query = Context.GetHttpContext()?.Request.Query;
        var clientType = query?["clientType"].ToString();
        var cpId       = query?["cpId"].ToString();
        var idTag      = query?["idTag"].ToString();

        switch (clientType)
        {
            // ── Charge Point ──────────────────────────────────────────────────
            // Register in the in-memory map so OcppMessage() knows who sent it.
            // Join group "CP:{cpId}" so CSMS can target it with remote commands.
            // Join group "all_cp" for any future broadcast-to-all-CPs use.
            case "cp" when !string.IsNullOrEmpty(cpId):
                lock (_cpLock) _cpConnections[Context.ConnectionId] = cpId;
                await Groups.AddToGroupAsync(Context.ConnectionId, $"CP:{cpId}");
                await Groups.AddToGroupAsync(Context.ConnectionId, "all_cp");
                _logger.LogInformation("[CP CONNECTED] {CpId} → {ConnId}", cpId, Context.ConnectionId);
                break;

            // ── CSMS Operator App ─────────────────────────────────────────────
            // Joins group "csms" — receives all CP events and can send remote commands.
            case "csms":
                await Groups.AddToGroupAsync(Context.ConnectionId, "csms");
                _logger.LogInformation("[CSMS CONNECTED] {ConnId}", Context.ConnectionId);
                break;

            // ── End-User Client App ───────────────────────────────────────────
            // Joins group "client:{idTag}" — only receives events for their own sessions.
            // This keeps users isolated from each other's charging data.
            case "client" when !string.IsNullOrEmpty(idTag):
                await Groups.AddToGroupAsync(Context.ConnectionId, $"client:{idTag}");
                _logger.LogInformation("[CLIENT CONNECTED] idTag={IdTag} {ConnId}", idTag, Context.ConnectionId);
                break;

            default:
                _logger.LogWarning("[UNKNOWN CLIENT] {ConnId} — missing ?clientType", Context.ConnectionId);
                break;
        }

        await base.OnConnectedAsync();
    }

    /// <summary>
    /// Called automatically when any client disconnects (graceful or dropped).
    /// If it was a CP, we mark it offline in the DB and notify the CSMS app.
    /// </summary>
    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        // Check if the disconnected connection was a Charge Point
        string? cpId = null;
        lock (_cpLock)
        {
            if (_cpConnections.TryGetValue(Context.ConnectionId, out cpId))
                _cpConnections.Remove(Context.ConnectionId); // clean up registry
        }

        if (cpId != null)
        {
            _logger.LogInformation("[CP DISCONNECTED] {CpId}", cpId);

            // Mark the CP as offline in the database
            var cp = await _db.ChargePoints.FirstOrDefaultAsync(c => c.ChargePointId == cpId);
            if (cp != null)
            {
                cp.IsOnline = false;
                await _db.SaveChangesAsync();
            }

            // Push "offline" notification to all connected CSMS apps
            await Clients.Group("csms").SendAsync("ChargePointOffline", new
            {
                ChargePointId = cpId,
                Timestamp = DateTime.UtcNow
            });
        }

        await base.OnDisconnectedAsync(exception);
    }

    // =========================================================================
    // ENTRY POINT: CP → BACKEND
    // The CP sends all OCPP messages through this single method.
    // =========================================================================

    /// <summary>
    /// Main entry point for all messages coming FROM the Charge Point.
    ///
    /// The CP sends a raw OCPP JSON frame string, e.g.:
    ///   [2, "abc-123", "BootNotification", { "chargePointVendor": "SimCo", ... }]
    ///
    /// We parse it, route to the right handler, and return the CALLRESULT frame:
    ///   [3, "abc-123", { "status": "Accepted", "currentTime": "...", "interval": 30 }]
    ///
    /// Returns a CALLERROR frame on any failure.
    /// </summary>
    public async Task<string> OcppMessage(string rawFrame)
    {
        // Look up which CP this connection belongs to
        string? cpId = null;
        lock (_cpLock) _cpConnections.TryGetValue(Context.ConnectionId, out cpId);

        if (cpId == null)
        {
            // Connection not registered — reject immediately
            _logger.LogWarning("OcppMessage from unknown connection {ConnId}", Context.ConnectionId);
            return BuildError("", "SecurityError", "Unknown charge point — connect with ?clientType=cp&cpId=...");
        }

        // Parse the JSON array frame
        JsonElement frame;
        try
        {
            frame = JsonSerializer.Deserialize<JsonElement>(rawFrame);
        }
        catch
        {
            return BuildError("", "FormationViolation", "Invalid JSON");
        }

        // Validate: must be an array with at least [msgType, msgId, ...]
        if (frame.ValueKind != JsonValueKind.Array || frame.GetArrayLength() < 3)
            return BuildError("", "FormationViolation", "Expected array with >= 3 elements");

        var msgType = frame[0].GetInt32();   // 2 = CALL, 3 = CALLRESULT, 4 = CALLERROR
        var msgId   = frame[1].GetString() ?? "";

        // Persist every inbound frame to the message log table for auditing
        await LogMessageAsync(
            cpId,
            direction: "CP->CSMS",
            action: msgType == 2 ? frame[2].GetString() ?? "?" : "RESULT",
            msgId,
            rawFrame
        );

        // Route by message type
        return msgType switch
        {
            2 => await HandleCall(cpId, msgId, frame),           // CP is making a request
            3 => await HandleCallResult(cpId, msgId, frame),     // CP is ACKing a remote command
            _ => BuildError(msgId, "FormationViolation", $"Unknown message type {msgType}")
        };
    }

    // =========================================================================
    // CALL ROUTER — dispatches each OCPP action to its handler
    // =========================================================================

    /// <summary>
    /// Routes an incoming CALL frame to the correct handler based on the action name.
    /// All handlers return an object that gets wrapped into a CALLRESULT frame.
    /// Any unhandled action returns a CALLERROR with "NotImplemented".
    /// </summary>
    private async Task<string> HandleCall(string cpId, string msgId, JsonElement frame)
    {
        var action  = frame[2].GetString() ?? "";
        // payload is optional per OCPP spec — default(JsonElement) if absent
        var payload = frame.GetArrayLength() > 3 ? frame[3] : default;

        _logger.LogInformation("[{CpId}] ← {Action}", cpId, action);

        try
        {
            // Each handler returns the raw response payload object.
            // Note: Heartbeat is sync because it returns immediately and fires
            // the DB update in the background (fire-and-forget via async void).
            var responsePayload = action switch
            {
                "BootNotification"              => await HandleBootNotification(cpId, payload),
                "Heartbeat"                     => HandleHeartbeat(),
                "Authorize"                     => await HandleAuthorize(cpId, payload),
                "StartTransaction"              => await HandleStartTransaction(cpId, payload),
                "StopTransaction"               => await HandleStopTransaction(cpId, payload),
                "StatusNotification"            => await HandleStatusNotification(cpId, payload),
                "MeterValues"                   => await HandleMeterValues(cpId, payload),
                "DataTransfer"                  => HandleDataTransfer(payload),
                "DiagnosticsStatusNotification" => HandleEmpty(),  // spec requires empty {}
                "FirmwareStatusNotification"    => HandleEmpty(),  // spec requires empty {}
                _ => throw new NotSupportedException($"Action '{action}' not implemented")
            };

            // Wrap the response object into a CALLRESULT frame and log it
            var result = BuildCallResult(msgId, responsePayload);
            await LogMessageAsync(cpId, "CSMS->CP", action + "Response", msgId, result);
            return result;
        }
        catch (NotSupportedException ex)
        {
            _logger.LogWarning("[{CpId}] Not implemented: {Action}", cpId, action);
            return BuildError(msgId, "NotImplemented", ex.Message);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[{CpId}] Error handling {Action}", cpId, action);
            return BuildError(msgId, "InternalError", ex.Message);
        }
    }

    /// <summary>
    /// Handles a CALLRESULT frame (msgType = 3) sent by the CP.
    /// This happens when the CP acknowledges a remote command we sent earlier
    /// (e.g. RemoteStartTransaction → CP replies with { status: "Accepted" }).
    /// We log it but don't send anything back — CALLRESULT has no reply.
    /// </summary>
    private Task<string> HandleCallResult(string cpId, string msgId, JsonElement frame)
    {
        _logger.LogInformation("[{CpId}] ← CallResult ack for msgId={MsgId}", cpId, msgId);
        return Task.FromResult(""); // no response to a CALLRESULT per OCPP spec
    }

    // =========================================================================
    // OCPP ACTION HANDLERS  (CP → CSMS requests)
    // =========================================================================

    /// <summary>
    /// BootNotification — sent by the CP on startup (or after reset).
    /// We upsert the ChargePoint record, mark it online, then push a
    /// "ChargePointBooted" event to all connected CSMS apps.
    ///
    /// Response tells the CP: "Accepted", what time it is, and how often to heartbeat.
    /// </summary>
    private async Task<object> HandleBootNotification(string cpId, JsonElement payload)
    {
        var req = Deserialize<OcppBootNotificationRequest>(payload);

        // Upsert: create the CP record if it doesn't exist yet, otherwise update it
        var cp = await _db.ChargePoints
            .Include(c => c.Connectors)
            .FirstOrDefaultAsync(c => c.ChargePointId == cpId);

        if (cp == null)
        {
            cp = new ChargePoint { ChargePointId = cpId };
            _db.ChargePoints.Add(cp);
        }

        cp.Vendor          = req?.ChargePointVendor ?? "";
        cp.Model           = req?.ChargePointModel ?? "";
        cp.SerialNumber    = req?.ChargePointSerialNumber ?? "";
        cp.FirmwareVersion = req?.FirmwareVersion ?? "";
        cp.IsOnline        = true;
        cp.LastBootTime    = DateTime.UtcNow;
        cp.LastHeartbeat   = DateTime.UtcNow;

        await _db.SaveChangesAsync();

        // Notify all CSMS operator apps that this CP just came online
        await Clients.Group("csms").SendAsync("ChargePointBooted", new
        {
            ChargePointId = cpId,
            cp.Vendor,
            cp.Model,
            cp.SerialNumber,
            cp.FirmwareVersion,
            Timestamp = DateTime.UtcNow
        });

        // Tell the CP it's accepted and to send a heartbeat every 30 seconds
        return new OcppBootNotificationResponse(
            Status: "Accepted",
            CurrentTime: DateTime.UtcNow.ToString("o"),
            Interval: 30
        );
    }

    /// <summary>
    /// Heartbeat — sent periodically by the CP to prove it's still alive.
    ///
    /// We return the current time immediately (the CP uses this to sync its clock),
    /// then fire-and-forget the DB update + CSMS notification in the background.
    /// This keeps the response latency low since the CP is just waiting for a timestamp.
    ///
    /// Why async void for UpdateHeartbeatAsync?
    ///   HandleHeartbeat() must be synchronous to fit the action switch expression.
    ///   async void lets us kick off async work without making the caller await it.
    /// </summary>
    private object HandleHeartbeat()
    {
        UpdateHeartbeatAsync(); // fire-and-forget — runs in background, no await needed
        return new OcppHeartbeatResponse(CurrentTime: DateTime.UtcNow.ToString("o"));
    }

    /// <summary>
    /// Background work for Heartbeat: updates LastHeartbeat in DB and
    /// notifies the CSMS. Runs after the response is already sent to the CP.
    /// </summary>
    private async void UpdateHeartbeatAsync()
    {
        try
        {
            // Re-read cpId from the connection registry (Context is still valid here)
            string? cpId = null;
            lock (_cpLock) _cpConnections.TryGetValue(Context.ConnectionId, out cpId);
            if (cpId == null) return;

            var cp = await _db.ChargePoints.FirstOrDefaultAsync(c => c.ChargePointId == cpId);
            if (cp != null)
            {
                cp.LastHeartbeat = DateTime.UtcNow;
                cp.IsOnline      = true;
                await _db.SaveChangesAsync();
            }

            // Let the CSMS know this CP is still alive with the latest timestamp
            await Clients.Group("csms").SendAsync("HeartbeatReceived", new
            {
                ChargePointId = cpId,
                Timestamp     = DateTime.UtcNow
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "UpdateHeartbeat failed");
        }
    }

    /// <summary>
    /// Authorize — CP asks "is this RFID tag allowed to charge?"
    /// We look up the tag in our IdTags table and return Accepted/Invalid/Blocked/Expired.
    /// The CSMS is notified of every authorization attempt for auditing.
    /// </summary>
    private async Task<object> HandleAuthorize(string cpId, JsonElement payload)
    {
        var req      = Deserialize<OcppAuthorizeRequest>(payload);
        var idTagInfo = await AuthorizeTagAsync(req?.IdTag ?? "");

        // Notify CSMS of the authorization attempt (accepted or not)
        await Clients.Group("csms").SendAsync("AuthorizeRequest", new
        {
            ChargePointId = cpId,
            IdTag  = req?.IdTag,
            Status = idTagInfo.Status
        });

        return new OcppAuthorizeResponse(IdTagInfo: idTagInfo);
    }

    /// <summary>
    /// StartTransaction — CP reports that a charging session has begun.
    ///
    /// Flow:
    ///   1. Re-authorize the tag (OCPP requires authorization at transaction start too)
    ///   2. Ensure the connector record exists in DB
    ///   3. Generate a unique transaction ID
    ///   4. Persist the transaction with status=Active
    ///   5. Mark the connector as Charging
    ///   6. Push TransactionStarted to CSMS and to the specific end-user
    /// </summary>
    private async Task<object> HandleStartTransaction(string cpId, JsonElement payload)
    {
        var req = Deserialize<OcppStartTransactionRequest>(payload);
        if (req == null) throw new ArgumentException("Invalid StartTransaction payload");

        // Authorize the tag — if not accepted, return early with status only (no txId)
        var idTagInfo = await AuthorizeTagAsync(req.IdTag);
        if (idTagInfo.Status != "Accepted")
        {
            return new OcppStartTransactionResponse(TransactionId: 0, IdTagInfo: idTagInfo);
        }

        var cp = await _db.ChargePoints
            .Include(c => c.Connectors)
            .FirstOrDefaultAsync(c => c.ChargePointId == cpId);

        if (cp == null) throw new InvalidOperationException($"ChargePoint {cpId} not found");

        // Get or create the connector row (CPs auto-register connectors on first use)
        var connector = cp.Connectors.FirstOrDefault(c => c.ConnectorId == req.ConnectorId);
        if (connector == null)
        {
            connector = new Connector { ChargePointId = cp.Id, ConnectorId = req.ConnectorId };
            _db.Connectors.Add(connector);
            await _db.SaveChangesAsync();
        }

        // Generate the next transaction ID (thread-safe, persisted counter)
        var txId = await _txIdService.NextAsync();

        var transaction = new Transaction
        {
            TransactionId  = txId,
            ChargePointId  = cp.Id,
            ConnectorId    = connector.Id,       // DB FK
            ConnectorNumber = req.ConnectorId,   // 1-based OCPP connector number
            IdTag          = req.IdTag,
            MeterStart     = req.MeterStart,     // energy in Wh at session start
            StartTime      = DateTime.TryParse(req.Timestamp, out var st) ? st : DateTime.UtcNow,
            Status         = TransactionStatus.Active
        };

        _db.Transactions.Add(transaction);
        connector.Status          = ConnectorStatus.Charging;
        connector.StatusTimestamp = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        var evt = new TransactionStartedEvent(
            TransactionId: txId,
            ChargePointId: cpId,
            ConnectorId:   req.ConnectorId,
            IdTag:         req.IdTag,
            StartTime:     transaction.StartTime,
            MeterStart:    req.MeterStart
        );

        // Notify CSMS (for the operator dashboard)
        await Clients.Group("csms").SendAsync("TransactionStarted", evt);
        // Notify ONLY the end-user whose tag started this session
        await Clients.Group($"client:{req.IdTag}").SendAsync("TransactionStarted", evt);

        return new OcppStartTransactionResponse(TransactionId: txId, IdTagInfo: idTagInfo);
    }

    /// <summary>
    /// StopTransaction — CP reports that a charging session has ended.
    ///
    /// Flow:
    ///   1. Find the active transaction by transactionId
    ///   2. Calculate energy delivered (meterStop - meterStart) in Wh → kWh
    ///   3. Mark transaction as Completed, set stop time and reason
    ///   4. Set connector back to Available
    ///   5. Push TransactionStopped to CSMS and to the specific end-user
    /// </summary>
    private async Task<object> HandleStopTransaction(string cpId, JsonElement payload)
    {
        var req = Deserialize<OcppStopTransactionRequest>(payload);
        if (req == null) throw new ArgumentException("Invalid StopTransaction payload");

        var transaction = await _db.Transactions
            .Include(t => t.Connector)
            .FirstOrDefaultAsync(t => t.TransactionId == req.TransactionId);

        if (transaction == null)
        {
            // Could happen if the backend restarted mid-session — log and return gracefully
            _logger.LogWarning("[{CpId}] StopTransaction for unknown TX {TxId}", cpId, req.TransactionId);
            return new OcppStopTransactionResponse(IdTagInfo: null);
        }

        var stopTime  = DateTime.TryParse(req.Timestamp, out var st) ? st : DateTime.UtcNow;
        var energyWh  = req.MeterStop - transaction.MeterStart; // total energy this session

        transaction.Status             = TransactionStatus.Completed;
        transaction.MeterStop          = req.MeterStop;
        transaction.StopTime           = stopTime;
        transaction.StopReason         = req.Reason;                  // "Local", "Remote", "EVDisconnected", etc.
        transaction.EnergyDeliveredKwh = energyWh / 1000.0;          // convert Wh → kWh

        // Release the connector back to Available
        if (transaction.Connector != null)
        {
            transaction.Connector.Status          = ConnectorStatus.Available;
            transaction.Connector.StatusTimestamp = DateTime.UtcNow;
        }

        await _db.SaveChangesAsync();

        var evt = new TransactionStoppedEvent(
            TransactionId:      req.TransactionId,
            ChargePointId:      cpId,
            ConnectorId:        transaction.ConnectorNumber,
            IdTag:              transaction.IdTag,
            StopTime:           stopTime,
            MeterStop:          req.MeterStop,
            EnergyDeliveredKwh: energyWh / 1000.0,
            Reason:             req.Reason
        );

        await Clients.Group("csms").SendAsync("TransactionStopped", evt);
        await Clients.Group($"client:{transaction.IdTag}").SendAsync("TransactionStopped", evt);

        // Optionally re-authorize the tag on stop (spec allows this)
        OcppIdTagInfo? idTagInfo = null;
        if (!string.IsNullOrEmpty(req.IdTag))
            idTagInfo = await AuthorizeTagAsync(req.IdTag);

        return new OcppStopTransactionResponse(IdTagInfo: idTagInfo);
    }

    /// <summary>
    /// StatusNotification — CP reports a connector's current status.
    /// Called after BootNotification and whenever connector state changes
    /// (Available → Preparing → Charging → Finishing → Available, etc.)
    ///
    /// ConnectorId 0 = the charge point itself (not a connector).
    /// We only persist status for connectorId > 0 (real connectors).
    /// After saving, we push the full CP status snapshot to the CSMS.
    /// </summary>
    private async Task<object> HandleStatusNotification(string cpId, JsonElement payload)
    {
        var req = Deserialize<OcppStatusNotificationRequest>(payload);
        if (req == null) return new { };

        if (req.ConnectorId > 0) // skip connectorId=0 (whole CP status, not persisted per connector)
        {
            var cp = await _db.ChargePoints
                .Include(c => c.Connectors)
                .FirstOrDefaultAsync(c => c.ChargePointId == cpId);

            if (cp != null)
            {
                // Auto-create the connector row if it's the first time we've seen it
                var connector = cp.Connectors.FirstOrDefault(c => c.ConnectorId == req.ConnectorId);
                if (connector == null)
                {
                    connector = new Connector { ChargePointId = cp.Id, ConnectorId = req.ConnectorId };
                    _db.Connectors.Add(connector);
                }

                // Parse the status and error code strings into enums
                if (Enum.TryParse<ConnectorStatus>(req.Status, true, out var status))
                    connector.Status = status;

                if (Enum.TryParse<ChargePointErrorCode>(req.ErrorCode, true, out var err))
                    connector.ErrorCode = err;

                connector.ErrorInfo       = req.Info;
                connector.StatusTimestamp = req.Timestamp != null
                    ? DateTime.Parse(req.Timestamp)
                    : DateTime.UtcNow;

                await _db.SaveChangesAsync();
            }
        }

        // Push a full status snapshot of this CP to the CSMS dashboard
        await PushCpStatusToCsmsAsync(cpId);

        return new { }; // OCPP spec: StatusNotification response is always empty
    }

    /// <summary>
    /// MeterValues — CP sends periodic energy/power/voltage/current readings.
    /// These come in during an active transaction at the configured interval (default 15s).
    ///
    /// We store each sample in the MeterValues table, then push real-time updates to:
    ///   - The CSMS (for the operator dashboard live view)
    ///   - The specific end-user app (so the user sees live kWh/power on their phone)
    /// </summary>
    private async Task<object> HandleMeterValues(string cpId, JsonElement payload)
    {
        var req = Deserialize<OcppMeterValuesRequest>(payload);
        if (req == null) return new { };

        // Only process if there's a transaction ID and actual meter value entries
        if (req.TransactionId.HasValue && req.MeterValue?.Count > 0)
        {
            var transaction = await _db.Transactions
                .FirstOrDefaultAsync(t => t.TransactionId == req.TransactionId.Value);

            if (transaction != null)
            {
                foreach (var mv in req.MeterValue)
                {
                    // Each MeterValue entry can contain multiple sampled values
                    // (energy, power, voltage, current) with the same timestamp
                    var meterValue = new MeterValue
                    {
                        TransactionId = transaction.Id,
                        Timestamp     = DateTime.TryParse(mv.Timestamp, out var ts) ? ts : DateTime.UtcNow,
                        Context       = "Sample.Periodic"
                    };

                    // Map each measurand to its typed column
                    foreach (var sv in mv.SampledValue ?? new())
                    {
                        if (!double.TryParse(sv.Value, out var val)) continue;
                        switch (sv.Measurand)
                        {
                            case "Energy.Active.Import.Register": meterValue.EnergyWh  = val; break;
                            case "Power.Active.Import":           meterValue.PowerW    = val; break;
                            case "Voltage":                       meterValue.VoltageV  = val; break;
                            case "Current.Import":                meterValue.CurrentA  = val; break;
                        }
                    }

                    _db.MeterValues.Add(meterValue);

                    // Push live update immediately — don't wait for SaveChanges
                    var update = new TransactionUpdatedEvent(
                        TransactionId: req.TransactionId.Value,
                        EnergyWh:  meterValue.EnergyWh ?? 0,
                        PowerW:    meterValue.PowerW,
                        VoltageV:  meterValue.VoltageV,
                        CurrentA:  meterValue.CurrentA,
                        Timestamp: meterValue.Timestamp
                    );

                    await Clients.Group("csms").SendAsync("MeterValuesUpdated", update);
                    await Clients.Group($"client:{transaction.IdTag}").SendAsync("ChargingUpdate", update);
                }

                await _db.SaveChangesAsync(); // batch save all meter value rows
            }
        }

        return new { }; // OCPP spec: MeterValues response is always empty
    }

    // Vendor-specific data transfer — we accept it but don't process it
    private object HandleDataTransfer(JsonElement payload) => new { Status = "Accepted" };

    // These messages require an empty {} response per OCPP 1.6 spec
    private object HandleEmpty() => new { };

    // =========================================================================
    // REMOTE COMMANDS — CSMS → CP
    // These are called directly by the CSMS Flutter app via SignalR invoke().
    // Each one builds an OCPP CALL frame and pushes it to the target CP's group.
    // =========================================================================

    /// <summary>
    /// Tell a CP to start a charging session for a given idTag on a given connector.
    /// The CP will respond with a CALLRESULT { status: "Accepted" | "Rejected" }.
    /// </summary>
    public async Task<object> SendRemoteStartTransaction(string cpId, string idTag, int? connectorId)
    {
        var payload = new RemoteStartTransactionRequest(idTag, connectorId, null);
        return await SendRemoteCommand(cpId, "RemoteStartTransaction", payload);
    }

    /// <summary>
    /// Tell a CP to stop an active transaction by its transactionId.
    /// </summary>
    public async Task<object> SendRemoteStopTransaction(string cpId, int transactionId)
    {
        var payload = new RemoteStopTransactionRequest(transactionId);
        return await SendRemoteCommand(cpId, "RemoteStopTransaction", payload);
    }

    /// <summary>
    /// Change a connector's availability.
    /// type = "Operative" → bring it back online
    /// type = "Inoperative" → take it offline (e.g. for maintenance)
    /// connectorId = 0 applies to ALL connectors on the CP.
    /// </summary>
    public async Task<object> SendChangeAvailability(string cpId, int connectorId, string type)
    {
        var payload = new ChangeAvailabilityRequest(connectorId, type);
        return await SendRemoteCommand(cpId, "ChangeAvailability", payload);
    }

    /// <summary>
    /// Restart the CP.
    /// type = "Soft" → graceful restart (finishes active transactions first)
    /// type = "Hard" → immediate restart (like a power cycle)
    /// </summary>
    public async Task<object> SendReset(string cpId, string type)
    {
        var payload = new ResetRequest(type);
        return await SendRemoteCommand(cpId, "Reset", payload);
    }

    /// <summary>
    /// Unlock a connector's physical lock (useful if a cable gets stuck).
    /// Will fail if a transaction is active on that connector.
    /// </summary>
    public async Task<object> SendUnlockConnector(string cpId, int connectorId)
    {
        var payload = new UnlockConnectorRequest(connectorId);
        return await SendRemoteCommand(cpId, "UnlockConnector", payload);
    }

    /// <summary>
    /// Read configuration key(s) from the CP.
    /// Pass null or empty list to get all keys.
    /// </summary>
    public async Task<object> SendGetConfiguration(string cpId, List<string>? keys)
    {
        var payload = new GetConfigurationRequest(keys);
        return await SendRemoteCommand(cpId, "GetConfiguration", payload);
    }

    /// <summary>
    /// Change a single configuration key on the CP (e.g. HeartbeatInterval).
    /// </summary>
    public async Task<object> SendChangeConfiguration(string cpId, string key, string value)
    {
        var payload = new ChangeConfigurationRequest(key, value);
        return await SendRemoteCommand(cpId, "ChangeConfiguration", payload);
    }

    /// <summary>
    /// Ask the CP to send a specific message type immediately.
    /// Useful for forcing a status update or heartbeat on demand.
    /// requestedMessage: "Heartbeat" | "StatusNotification" | "BootNotification"
    /// </summary>
    public async Task<object> SendTriggerMessage(string cpId, string requestedMessage, int? connectorId)
    {
        var payload = new TriggerMessageRequest(requestedMessage, connectorId);
        return await SendRemoteCommand(cpId, "TriggerMessage", payload);
    }

    /// <summary>
    /// Tell the CP to clear its local authorization cache.
    /// </summary>
    public async Task<object> SendClearCache(string cpId)
    {
        return await SendRemoteCommand(cpId, "ClearCache", new { });
    }

    /// <summary>
    /// Shared helper for all remote commands.
    /// Builds the OCPP CALL frame [2, msgId, action, payload] and pushes it
    /// to the CP's SignalR group. Returns immediately — the CP's CALLRESULT
    /// comes back asynchronously via OcppMessage().
    /// </summary>
    private async Task<object> SendRemoteCommand(string cpId, string action, object payload)
    {
        var msgId    = Guid.NewGuid().ToString();
        var frame    = new object[] { 2, msgId, action, payload };
        var rawFrame = JsonSerializer.Serialize(frame, _jsonOpts);

        await LogMessageAsync(cpId, "CSMS->CP", action, msgId, rawFrame);
        _logger.LogInformation("[{CpId}] → {Action}", cpId, action);

        // Push the OCPP CALL frame to the CP — it will handle it and call OcppMessage() back
        await Clients.Group($"CP:{cpId}").SendAsync("OcppCommand", rawFrame);

        return new { MessageId = msgId, Action = action, Status = "Sent" };
    }

    // =========================================================================
    // CSMS QUERY METHODS — callable by the CSMS app to fetch current state
    // =========================================================================

    /// <summary>
    /// Returns all registered charge points with their connector statuses.
    /// Called by the CSMS app on startup to populate its dashboard.
    /// </summary>
    public async Task<object> GetAllChargePoints()
    {
        var cps = await _db.ChargePoints
            .Include(c => c.Connectors)
            .OrderBy(c => c.ChargePointId)
            .ToListAsync();

        return cps.Select(cp => new
        {
            cp.ChargePointId,
            cp.Vendor,
            cp.Model,
            cp.SerialNumber,
            cp.FirmwareVersion,
            cp.IsOnline,
            cp.LastHeartbeat,
            cp.LastBootTime,
            Connectors = cp.Connectors.Select(c => new
            {
                c.ConnectorId,
                Status    = c.Status.ToString(),
                ErrorCode = c.ErrorCode.ToString(),
                c.StatusTimestamp
            })
        });
    }

    /// <summary>
    /// Returns all currently active (in-progress) transactions across all CPs.
    /// Used by the CSMS dashboard to show live charging sessions.
    /// </summary>
    public async Task<object> GetActiveTransactions()
    {
        var txs = await _db.Transactions
            .Include(t => t.ChargePoint)
            .Where(t => t.Status == TransactionStatus.Active)
            .OrderByDescending(t => t.StartTime)
            .ToListAsync();

        return txs.Select(t => new
        {
            t.TransactionId,
            ChargePointId = t.ChargePoint.ChargePointId,
            t.ConnectorNumber,
            t.IdTag,
            t.StartTime,
            t.MeterStart,
            t.Status
        });
    }

    // =========================================================================
    // CLIENT APP QUERY METHODS — callable by the end-user app
    // =========================================================================

    /// <summary>
    /// Returns the last 20 transactions for a specific RFID tag.
    /// Used by the client app to show the user's charging history.
    /// Includes the most recent meter reading for each session.
    /// </summary>
    public async Task<object> GetMyTransactions(string idTag)
    {
        var txs = await _db.Transactions
            .Include(t => t.ChargePoint)
            .Include(t => t.MeterValues)
            .Where(t => t.IdTag == idTag)
            .OrderByDescending(t => t.StartTime)
            .Take(20)
            .ToListAsync();

        return txs.Select(t => new
        {
            t.TransactionId,
            ChargePointId = t.ChargePoint.ChargePointId,
            t.ConnectorNumber,
            t.IdTag,
            t.StartTime,
            t.StopTime,
            t.MeterStart,
            t.MeterStop,
            t.EnergyDeliveredKwh,
            Status        = t.Status.ToString(),
            t.StopReason,
            // Only return the latest meter reading (not the full history) for performance
            LatestMeterValue = t.MeterValues
                .OrderByDescending(m => m.Timestamp)
                .Select(m => new { m.EnergyWh, m.PowerW, m.VoltageV, m.CurrentA, m.Timestamp })
                .FirstOrDefault()
        });
    }

    /// <summary>
    /// Returns the currently active session for a specific tag, if any.
    /// Used by the client app on startup to resume displaying a live session.
    /// Returns { Active: false } if no session is in progress.
    /// </summary>
    public async Task<object> GetActiveTransactionForTag(string idTag)
    {
        var tx = await _db.Transactions
            .Include(t => t.ChargePoint)
            .Include(t => t.MeterValues)
            .Where(t => t.IdTag == idTag && t.Status == TransactionStatus.Active)
            .FirstOrDefaultAsync();

        if (tx == null) return new { Active = false };

        // Return the latest meter reading for the live energy/power display
        var latest = tx.MeterValues.OrderByDescending(m => m.Timestamp).FirstOrDefault();

        return new
        {
            Active        = true,
            tx.TransactionId,
            ChargePointId = tx.ChargePoint.ChargePointId,
            tx.ConnectorNumber,
            tx.StartTime,
            tx.MeterStart,
            EnergyWh = latest?.EnergyWh ?? 0,
            PowerW   = latest?.PowerW,
            VoltageV = latest?.VoltageV,
            CurrentA = latest?.CurrentA
        };
    }

    // =========================================================================
    // PRIVATE HELPERS
    // =========================================================================

    /// <summary>
    /// Looks up an RFID tag in the IdTags table and returns the OCPP-formatted
    /// authorization result. Handles: not found → Invalid, blocked → Blocked,
    /// expired → Expired, valid → Accepted.
    /// </summary>
    private async Task<OcppIdTagInfo> AuthorizeTagAsync(string tagId)
    {
        var tag = await _db.IdTags.FirstOrDefaultAsync(t => t.TagId == tagId);

        if (tag == null)
            return new OcppIdTagInfo("Invalid", null, null);

        if (tag.Status != AuthorizationStatus.Accepted)
            return new OcppIdTagInfo(tag.Status.ToString(), null, null);

        if (tag.ExpiryDate.HasValue && tag.ExpiryDate < DateTime.UtcNow)
            return new OcppIdTagInfo("Expired", tag.ExpiryDate.Value.ToString("o"), null);

        return new OcppIdTagInfo("Accepted", tag.ExpiryDate?.ToString("o"), tag.ParentTagId);
    }

    /// <summary>
    /// Builds a full CP status snapshot and pushes it to the "csms" group.
    /// Called after every StatusNotification so the CSMS always has the current picture.
    /// Includes which connector has which active transaction (if any).
    /// </summary>
    private async Task PushCpStatusToCsmsAsync(string cpId)
    {
        var cp = await _db.ChargePoints
            .Include(c => c.Connectors)
            .FirstOrDefaultAsync(c => c.ChargePointId == cpId);

        if (cp == null) return;

        // Get all active transactions for this CP so we can show which connector is busy
        var activeTransactions = await _db.Transactions
            .Where(t => t.Status == TransactionStatus.Active && t.ChargePoint.ChargePointId == cpId)
            .ToListAsync();

        var update = new ChargePointStatusUpdate(
            ChargePointId: cpId,
            IsOnline:      cp.IsOnline,
            LastHeartbeat: cp.LastHeartbeat,
            Connectors: cp.Connectors.Select(c =>
            {
                var activeTx = activeTransactions.FirstOrDefault(t => t.ConnectorNumber == c.ConnectorId);
                return new ConnectorStatusDto(
                    ConnectorId:         c.ConnectorId,
                    Status:              c.Status.ToString(),
                    ErrorCode:           c.ErrorCode.ToString(),
                    ActiveTransactionId: activeTx?.TransactionId  // null if connector is idle
                );
            })
        );

        await Clients.Group("csms").SendAsync("ChargePointStatusUpdate", update);
    }

    /// <summary>
    /// Wraps a response payload into an OCPP CALLRESULT frame: [3, msgId, payload]
    /// </summary>
    private static string BuildCallResult(string msgId, object payload)
    {
        var frame = new object[] { 3, msgId, payload };
        return JsonSerializer.Serialize(frame, _jsonOpts);
    }

    /// <summary>
    /// Builds an OCPP CALLERROR frame: [4, msgId, errorCode, description, {}]
    /// errorCode must be one of the OCPP-defined strings (e.g. "NotImplemented", "InternalError")
    /// </summary>
    private static string BuildError(string msgId, string errorCode, string description)
    {
        var frame = new object[] { 4, msgId, errorCode, description, new { } };
        return JsonSerializer.Serialize(frame, _jsonOpts);
    }

    /// <summary>
    /// Deserializes a JsonElement into a strongly-typed request object.
    /// Returns null if the element is undefined (missing payload).
    /// </summary>
    private static T? Deserialize<T>(JsonElement element)
    {
        var json = element.ValueKind == JsonValueKind.Undefined ? "{}" : element.GetRawText();
        return JsonSerializer.Deserialize<T>(json, _jsonOpts);
    }

    /// <summary>
    /// Persists a raw OCPP frame to the MessageLogs table for auditing and debugging.
    /// Silently swallows exceptions — logging failure must never break message processing.
    /// Truncates payloads over 4000 chars to keep the DB manageable.
    /// </summary>
    private async Task LogMessageAsync(string cpId, string direction, string action, string msgId, string payload)
    {
        try
        {
            _db.MessageLogs.Add(new OcppMessageLog
            {
                ChargePointId = cpId,
                Direction     = direction,   // "CP->CSMS" or "CSMS->CP"
                Action        = action,
                MessageId     = msgId,
                Payload       = payload.Length > 4000 ? payload[..4000] : payload,
                Timestamp     = DateTime.UtcNow
            });
            await _db.SaveChangesAsync();
        }
        catch { /* non-critical — never let logging break the main flow */ }
    }
}