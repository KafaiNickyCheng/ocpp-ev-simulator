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
}
