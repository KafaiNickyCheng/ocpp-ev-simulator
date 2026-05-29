// Controllers/ApiController.cs
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using OcppBackend.Data;
using OcppBackend.DTOs;
using OcppBackend.Hubs;
using OcppBackend.Models;

namespace OcppBackend.Controllers;

[ApiController]
[Route("api")]
public class ApiController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IHubContext<OcppHub> _hub;

    public ApiController(AppDbContext db, IHubContext<OcppHub> hub)
    {
        _db  = db;
        _hub = hub;
    }

    // ─── ChargePoints ────────────────────────────────────────────────────────

    /// <summary>List all registered charge points with connector status.</summary>
    [HttpGet("chargepoints")]
    public async Task<IActionResult> GetChargePoints()
    {
        var cps = await _db.ChargePoints
            .Include(c => c.Connectors)
            .OrderBy(c => c.ChargePointId)
            .ToListAsync();

        var result = cps.Select(cp => new
        {
            cp.ChargePointId,
            cp.Vendor,
            cp.Model,
            cp.SerialNumber,
            cp.FirmwareVersion,
            cp.IsOnline,
            cp.LastHeartbeat,
            cp.LastBootTime,
            Connectors = cp.Connectors.OrderBy(c => c.ConnectorId).Select(c => new
            {
                c.ConnectorId,
                Status = c.Status.ToString(),
                ErrorCode = c.ErrorCode.ToString(),
                c.ErrorInfo,
                c.StatusTimestamp
            })
        });

        return Ok(result);
    }

    /// <summary>Get a single charge point.</summary>
    [HttpGet("chargepoints/{cpId}")]
    public async Task<IActionResult> GetChargePoint(string cpId)
    {
        var cp = await _db.ChargePoints
            .Include(c => c.Connectors)
            .FirstOrDefaultAsync(c => c.ChargePointId == cpId);

        if (cp == null) return NotFound();

        Console.WriteLine("The cp is : ", cp);

        return Ok(cp);
    }

    /// <summary>Update charge point identity and connector count.</summary>
    [HttpPut("chargepoints/{cpId}")]
    public async Task<IActionResult> UpdateChargePoint(string cpId, [FromBody] UpdateChargePointRequest req)
    {
        var cp = await _db.ChargePoints
            .Include(c => c.Connectors)
            .FirstOrDefaultAsync(c => c.ChargePointId == cpId);

        if (cp == null) return NotFound();

        if (!string.IsNullOrWhiteSpace(req.Vendor))          cp.Vendor          = req.Vendor;
        if (!string.IsNullOrWhiteSpace(req.Model))           cp.Model           = req.Model;
        if (!string.IsNullOrWhiteSpace(req.SerialNumber))    cp.SerialNumber    = req.SerialNumber;
        if (!string.IsNullOrWhiteSpace(req.FirmwareVersion)) cp.FirmwareVersion = req.FirmwareVersion;

        if (req.ConnectorCount.HasValue && req.ConnectorCount.Value > 0)
        {
            var currentIds = cp.Connectors.Select(c => c.ConnectorId).ToHashSet();
            var desiredIds = Enumerable.Range(1, req.ConnectorCount.Value).ToHashSet();

            // Add new connectors
            foreach (var id in desiredIds.Except(currentIds))
                _db.Connectors.Add(new Connector
                {
                    ChargePointId = cp.Id,
                    ConnectorId   = id,
                    Status        = ConnectorStatus.Unavailable,
                });

            // Remove extra connectors only if no active transaction on them
            foreach (var c in cp.Connectors.Where(c => !desiredIds.Contains(c.ConnectorId)))
            {
                var hasActive = await _db.Transactions.AnyAsync(t =>
                    t.ConnectorId == c.Id && t.Status == TransactionStatus.Active);
                if (!hasActive) _db.Connectors.Remove(c);
            }
        }

        await _db.SaveChangesAsync();

        // Notify CSMS so its dashboard reflects the change immediately
        await _hub.Clients.Group("csms").SendAsync("ChargePointStatusUpdate", new ChargePointStatusUpdate(
            ChargePointId: cpId,
            IsOnline:      cp.IsOnline,
            LastHeartbeat: cp.LastHeartbeat,
            Connectors:    cp.Connectors.Select(c => new ConnectorStatusDto(
                ConnectorId:         c.ConnectorId,
                Status:              c.Status.ToString(),
                ErrorCode:           c.ErrorCode.ToString(),
                ActiveTransactionId: null
            ))
        ));

        return Ok(new { cp.ChargePointId, cp.Vendor, cp.Model, cp.SerialNumber, cp.FirmwareVersion });
    }

    // ─── Transactions ─────────────────────────────────────────────────────────

    /// <summary>List transactions (all or filtered by status/cpId/idTag).</summary>
    [HttpGet("transactions")]
    public async Task<IActionResult> GetTransactions(
        [FromQuery] string? cpId,
        [FromQuery] string? idTag,
        [FromQuery] string? status,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        var query = _db.Transactions
            .Include(t => t.ChargePoint)
            .AsQueryable();

        if (!string.IsNullOrEmpty(cpId))
            query = query.Where(t => t.ChargePoint.ChargePointId == cpId);

        if (!string.IsNullOrEmpty(idTag))
            query = query.Where(t => t.IdTag == idTag);

        if (!string.IsNullOrEmpty(status) && Enum.TryParse<TransactionStatus>(status, true, out var ts))
            query = query.Where(t => t.Status == ts);

        var total = await query.CountAsync();
        var items = await query
            .OrderByDescending(t => t.StartTime)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(t => new
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
                Status = t.Status.ToString(),
                t.StopReason
            })
            .ToListAsync();

        return Ok(new PagedResult<object>(items, total, page, pageSize));
    }

    /// <summary>Get transaction detail with meter values.</summary>
    [HttpGet("transactions/{txId:int}")]
    public async Task<IActionResult> GetTransaction(int txId)
    {
        var tx = await _db.Transactions
            .Include(t => t.ChargePoint)
            .Include(t => t.MeterValues)
            .FirstOrDefaultAsync(t => t.TransactionId == txId);

        if (tx == null) return NotFound();

        return Ok(new
        {
            tx.TransactionId,
            ChargePointId = tx.ChargePoint.ChargePointId,
            tx.ConnectorNumber,
            tx.IdTag,
            tx.StartTime,
            tx.StopTime,
            tx.MeterStart,
            tx.MeterStop,
            tx.EnergyDeliveredKwh,
            Status = tx.Status.ToString(),
            tx.StopReason,
            MeterValues = tx.MeterValues
                .OrderBy(m => m.Timestamp)
                .Select(m => new
                {
                    m.Timestamp,
                    m.EnergyWh,
                    m.PowerW,
                    m.VoltageV,
                    m.CurrentA
                })
        });
    }

    // ─── IdTags ───────────────────────────────────────────────────────────────

    /// <summary>List all RFID/ID tags.</summary>
    [HttpGet("tags")]
    public async Task<IActionResult> GetTags()
    {
        var tags = await _db.IdTags.OrderBy(t => t.TagId).ToListAsync();
        return Ok(tags);
    }

    /// <summary>Get a single tag.</summary>
    [HttpGet("tags/{tagId}")]
    public async Task<IActionResult> GetTag(string tagId)
    {
        var tag = await _db.IdTags.FirstOrDefaultAsync(t => t.TagId == tagId);
        if (tag == null) return NotFound();
        return Ok(tag);
    }

    /// <summary>Register a new ID tag.</summary>
    [HttpPost("tags")]
    public async Task<IActionResult> CreateTag([FromBody] CreateIdTagRequest req)
    {
        if (await _db.IdTags.AnyAsync(t => t.TagId == req.TagId))
            return Conflict(new { Error = $"Tag '{req.TagId}' already exists" });

        var tag = new IdTag
        {
            TagId = req.TagId,
            UserName = req.UserName,
            UserId = req.UserId,
            Note = req.Note,
            ExpiryDate = req.ExpiryDate,
            Status = AuthorizationStatus.Accepted,
            CreatedAt = DateTime.UtcNow
        };

        _db.IdTags.Add(tag);
        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(GetTag), new { tagId = tag.TagId }, tag);
    }

    /// <summary>Update tag status or details.</summary>
    [HttpPut("tags/{tagId}")]
    public async Task<IActionResult> UpdateTag(string tagId, [FromBody] UpdateIdTagRequest req)
    {
        var tag = await _db.IdTags.FirstOrDefaultAsync(t => t.TagId == tagId);
        if (tag == null) return NotFound();

        if (!Enum.TryParse<AuthorizationStatus>(req.Status, true, out var newStatus))
            return BadRequest(new { Error = "Invalid status. Use: Accepted, Blocked, Expired, Invalid" });

        tag.UserName = req.UserName ?? tag.UserName;
        tag.Note = req.Note ?? tag.Note;
        tag.Status = newStatus;
        tag.ExpiryDate = req.ExpiryDate ?? tag.ExpiryDate;

        await _db.SaveChangesAsync();
        return Ok(tag);
    }

    /// <summary>Delete a tag.</summary>
    [HttpDelete("tags/{tagId}")]
    public async Task<IActionResult> DeleteTag(string tagId)
    {
        var tag = await _db.IdTags.FirstOrDefaultAsync(t => t.TagId == tagId);
        if (tag == null) return NotFound();

        _db.IdTags.Remove(tag);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    // ─── Message Logs ─────────────────────────────────────────────────────────

    /// <summary>Get OCPP message logs, optionally filtered by CP.</summary>
    [HttpGet("logs")]
    public async Task<IActionResult> GetLogs(
        [FromQuery] string? cpId,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var query = _db.MessageLogs.AsQueryable();

        if (!string.IsNullOrEmpty(cpId))
            query = query.Where(l => l.ChargePointId == cpId);

        var total = await query.CountAsync();
        var items = await query
            .OrderByDescending(l => l.Timestamp)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        return Ok(new PagedResult<OcppMessageLog>(items, total, page, pageSize));
    }

    // ─── Health ───────────────────────────────────────────────────────────────

    [HttpGet("health")]
    public IActionResult Health() => Ok(new
    {
        Status = "ok",
        Timestamp = DateTime.UtcNow,
        Service = "OCPP 1.6 Backend"
    });


    // ─── Remote Commands (for LIFF / End User app) ───────────────────────────────
    private static string BuildRemoteStart(string idTag, int connectorId)
    {
        var frame = new object[]
        {
            2, Guid.NewGuid().ToString(), "RemoteStartTransaction",
            new { idTag, connectorId }
        };
        return System.Text.Json.JsonSerializer.Serialize(frame,
            new System.Text.Json.JsonSerializerOptions
            { PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase });
    }

    private static string BuildRemoteStop(int transactionId)
    {
        var frame = new object[]
        {
            2, Guid.NewGuid().ToString(), "RemoteStopTransaction",
            new { transactionId }
        };
        return System.Text.Json.JsonSerializer.Serialize(frame,
            new System.Text.Json.JsonSerializerOptions
            { PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase });
    }

    /// <summary>Trigger RemoteStart for a specific connector.</summary>
    [HttpPost("chargepoints/{cpId}/remote-start")]
    public async Task<IActionResult> RemoteStart(string cpId, [FromBody] RemoteStartRequest req)
    {
        var cp = await _db.ChargePoints.FirstOrDefaultAsync(c => c.ChargePointId == cpId);
        if (cp == null) return NotFound(new { Error = "ChargePoint not found" });
        if (!cp.IsOnline) return BadRequest(new { Error = "ChargePoint is offline" });

        var tag = await _db.IdTags.FirstOrDefaultAsync(t => t.TagId == req.IdTag);
        if (tag == null || tag.Status != AuthorizationStatus.Accepted)
            return BadRequest(new { Error = "IdTag not authorized" });

        await _hub.Clients
            .Group($"CP:{cpId}")
            .SendAsync("OcppCommand", BuildRemoteStart(req.IdTag, req.ConnectorId));

        return Ok(new { Status = "Sent", ChargePointId = cpId, req.ConnectorId, req.IdTag });
    }

    /// <summary>Trigger RemoteStop for an active transaction.</summary>
    [HttpPost("chargepoints/{cpId}/remote-stop")]
    public async Task<IActionResult> RemoteStop(string cpId, [FromBody] RemoteStopRequest req)
    {
        var tx = await _db.Transactions
            .FirstOrDefaultAsync(t => t.TransactionId == req.TransactionId
                                && t.Status == TransactionStatus.Active);

        if (tx == null) return NotFound(new { Error = "Active transaction not found" });

        await _hub.Clients.Group($"CP:{cpId}")
            .SendAsync("OcppCommand", BuildRemoteStop(req.TransactionId));

        return Ok(new { Status = "Sent", req.TransactionId });
    }

    // ─── Tags — LINE user endpoints ───────────────────────────────────────────────

    /// <summary>Get tag by lineUserId (used by LIFF app on load).</summary>
    [HttpGet("tags/by-line/{lineUserId}")]
    public async Task<IActionResult> GetTagByLineUser(string lineUserId)
    {
        var tag = await _db.IdTags.FirstOrDefaultAsync(t => t.LineUserId == lineUserId);
        if (tag == null) return NotFound();
        return Ok(tag);
    }

    /// <summary>Create tag — auto-generates TagId if not provided (for LINE users).</summary>
    // Override the existing POST /api/tags to support LineUserId + auto TagId
    [HttpPost("tags/line")]
    public async Task<IActionResult> CreateLineTag([FromBody] CreateLineTagRequest req)
    {
        // Check if this LINE user already has a tag
        if (await _db.IdTags.AnyAsync(t => t.LineUserId == req.LineUserId))
            return Conflict(new { Error = "Tag already exists for this LINE user" });

        // Auto-generate a short unique TagId (LINE-XXXXXXXX format)
        var tagId = $"LINE-{Guid.NewGuid().ToString("N")[..8].ToUpper()}";

        var tag = new IdTag
        {
            TagId      = tagId,
            LineUserId = req.LineUserId,
            UserName   = req.DisplayName,
            Status     = AuthorizationStatus.Accepted,
            CreatedAt  = DateTime.UtcNow
        };

        _db.IdTags.Add(tag);
        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(GetTag), new { tagId = tag.TagId }, tag);
    }

    // ─── Transactions — LINE user endpoints ──────────────────────────────────────

    /// <summary>Get transaction history for a LINE user.</summary>
    [HttpGet("transactions/by-line/{lineUserId}")]
    public async Task<IActionResult> GetTransactionsByLineUser(
        string lineUserId,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        var tag = await _db.IdTags.FirstOrDefaultAsync(t => t.LineUserId == lineUserId);
        if (tag == null) return Ok(new List<object>());

        var query = _db.Transactions
            .Include(t => t.ChargePoint)
            .Where(t => t.IdTag == tag.TagId)
            .OrderByDescending(t => t.StartTime);

        var total = await query.CountAsync();
        var items = await query
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(t => new
            {
                t.Id,
                t.TransactionId,
                ChargePointId = t.ChargePoint.ChargePointId,
                t.ConnectorNumber,
                t.IdTag,
                t.StartTime,
                t.StopTime,
                t.MeterStart,
                t.MeterStop,
                t.EnergyDeliveredKwh,
                Status = t.Status.ToString(),
                t.StopReason
            })
            .ToListAsync();

        return Ok(new PagedResult<object>(items, total, page, pageSize));
    }

    /// <summary>Get active session for a LINE user.</summary>
    [HttpGet("transactions/active/by-line/{lineUserId}")]
    public async Task<IActionResult> GetActiveTransactionByLineUser(string lineUserId)
    {
        var tag = await _db.IdTags.FirstOrDefaultAsync(t => t.LineUserId == lineUserId);
        if (tag == null) return Ok(null);

        var tx = await _db.Transactions
            .Include(t => t.ChargePoint)
            .Include(t => t.MeterValues)
            .Where(t => t.IdTag == tag.TagId && t.Status == TransactionStatus.Active)
            .FirstOrDefaultAsync();

        if (tx == null) return Ok(null);

        var latest = tx.MeterValues.OrderByDescending(m => m.Timestamp).FirstOrDefault();

        return Ok(new
        {
            tx.TransactionId,
            ChargePointId    = tx.ChargePoint.ChargePointId,
            tx.ConnectorNumber,
            tx.IdTag,
            tx.StartTime,
            tx.MeterStart,
            CurrentEnergyWh  = latest?.EnergyWh,
            PowerW           = latest?.PowerW,
            VoltageV         = latest?.VoltageV,
            CurrentA         = latest?.CurrentA
        });
    }
}
