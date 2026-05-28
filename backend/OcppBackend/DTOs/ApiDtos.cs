// DTOs/ApiDtos.cs
namespace OcppBackend.DTOs;

// ─── IdTag management ────────────────────────────────────────────────────────

public record CreateIdTagRequest(
    string TagId,
    string? UserName,
    string? UserId,
    string? Note,
    DateTime? ExpiryDate
);

public record UpdateIdTagRequest(
    string? UserName,
    string? Note,
    string Status,    // "Accepted" | "Blocked" | "Invalid"
    DateTime? ExpiryDate
);

public record UpdateChargePointRequest(
    string? Vendor,
    string? Model,
    string? SerialNumber,
    string? FirmwareVersion,
    int? ConnectorCount
);

// ─── Pagination ───────────────────────────────────────────────────────────────

public record PagedResult<T>(IEnumerable<T> Items, int Total, int Page, int PageSize);
