// Services/TransactionIdService.cs
using Microsoft.EntityFrameworkCore;
using OcppBackend.Data;

namespace OcppBackend.Services;

/// <summary>
/// Thread-safe incrementing OCPP transaction ID generator backed by SQLite.
/// </summary>
public class TransactionIdService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private int _counter = -1;
    private readonly SemaphoreSlim _lock = new(1, 1);

    public TransactionIdService(IServiceScopeFactory scopeFactory)
    {
        _scopeFactory = scopeFactory;
    }

    public async Task<int> NextAsync()
    {
        await _lock.WaitAsync();
        try
        {
            if (_counter < 0)
            {
                // Initialize from DB max on first call
                using var scope = _scopeFactory.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var max = await db.Transactions.MaxAsync(t => (int?)t.TransactionId) ?? 999;
                _counter = max;
            }
            return ++_counter;
        }
        finally
        {
            _lock.Release();
        }
    }
}
