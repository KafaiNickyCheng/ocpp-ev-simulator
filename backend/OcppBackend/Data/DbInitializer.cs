// Data/DbInitializer.cs
using Microsoft.EntityFrameworkCore;

namespace OcppBackend.Data;

public static class DbInitializer
{
    public static async Task InitializeAsync(IServiceProvider services)
    {
        using var scope = services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        // Auto-apply migrations (creates DB on first run)
        await db.Database.MigrateAsync();
    }
}
