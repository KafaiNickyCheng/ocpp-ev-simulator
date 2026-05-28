// Data/AppDbContext.cs
using Microsoft.EntityFrameworkCore;
using OcppBackend.Models;

namespace OcppBackend.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<ChargePoint> ChargePoints => Set<ChargePoint>();
    public DbSet<Connector> Connectors => Set<Connector>();
    public DbSet<IdTag> IdTags => Set<IdTag>();
    public DbSet<Transaction> Transactions => Set<Transaction>();
    public DbSet<MeterValue> MeterValues => Set<MeterValue>();
    public DbSet<OcppMessageLog> MessageLogs => Set<OcppMessageLog>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // ChargePoint
        modelBuilder.Entity<ChargePoint>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.ChargePointId).IsUnique();
            e.Property(x => x.ChargePointId).HasMaxLength(50).IsRequired();
        });

        // Connector
        modelBuilder.Entity<Connector>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasIndex(x => new { x.ChargePointId, x.ConnectorId }).IsUnique();
            e.HasOne(x => x.ChargePoint)
             .WithMany(x => x.Connectors)
             .HasForeignKey(x => x.ChargePointId);
            e.Property(x => x.Status).HasConversion<string>();
            e.Property(x => x.ErrorCode).HasConversion<string>();
        });

        // IdTag
        modelBuilder.Entity<IdTag>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.TagId).IsUnique();
            e.Property(x => x.TagId).HasMaxLength(20).IsRequired();
            e.Property(x => x.Status).HasConversion<string>();
        });

        // Transaction
        modelBuilder.Entity<Transaction>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.TransactionId).IsUnique();
            e.HasOne(x => x.ChargePoint)
             .WithMany(x => x.Transactions)
             .HasForeignKey(x => x.ChargePointId);
            e.HasOne(x => x.Connector)
             .WithMany(x => x.Transactions)
             .HasForeignKey(x => x.ConnectorId);
            e.Property(x => x.Status).HasConversion<string>();
        });

        // MeterValue
        modelBuilder.Entity<MeterValue>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasOne(x => x.Transaction)
             .WithMany(x => x.MeterValues)
             .HasForeignKey(x => x.TransactionId);
        });

        // OcppMessageLog
        modelBuilder.Entity<OcppMessageLog>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.ChargePointId);
            e.HasIndex(x => x.Timestamp);
        });

        // ─── Seed data ────────────────────────────────────────────────────────
        modelBuilder.Entity<IdTag>().HasData(
            new IdTag { Id = 1, TagId = "TAG-001",    UserName = "Alice",  Status = AuthorizationStatus.Accepted, CreatedAt = new DateTime(2024, 1, 1, 0, 0, 0, DateTimeKind.Utc) },
            new IdTag { Id = 2, TagId = "TAG-002",    UserName = "Bob",    Status = AuthorizationStatus.Accepted, CreatedAt = new DateTime(2024, 1, 1, 0, 0, 0, DateTimeKind.Utc) },
            new IdTag { Id = 3, TagId = "TAG-003",    UserName = "Carol",  Status = AuthorizationStatus.Accepted, CreatedAt = new DateTime(2024, 1, 1, 0, 0, 0, DateTimeKind.Utc) },
            new IdTag { Id = 4, TagId = "RFID-ADMIN", UserName = "Admin",  Status = AuthorizationStatus.Accepted, CreatedAt = new DateTime(2024, 1, 1, 0, 0, 0, DateTimeKind.Utc) },
            new IdTag { Id = 5, TagId = "RFID-USER1", UserName = "User1",  Status = AuthorizationStatus.Accepted, CreatedAt = new DateTime(2024, 1, 1, 0, 0, 0, DateTimeKind.Utc) },
            new IdTag { Id = 6, TagId = "RFID-USER2", UserName = "User2",  Status = AuthorizationStatus.Accepted, CreatedAt = new DateTime(2024, 1, 1, 0, 0, 0, DateTimeKind.Utc) },
            new IdTag { Id = 7, TagId = "REMOTE-TAG", UserName = "Remote", Status = AuthorizationStatus.Accepted, CreatedAt = new DateTime(2024, 1, 1, 0, 0, 0, DateTimeKind.Utc) }
        );
    }
}
