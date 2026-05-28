// Program.cs
using Microsoft.EntityFrameworkCore;
using OcppBackend.Data;
using OcppBackend.Hubs;
using OcppBackend.Services;

var builder = WebApplication.CreateBuilder(args);

// ─── Services ─────────────────────────────────────────────────────────────────

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlite(
        builder.Configuration.GetConnectionString("DefaultConnection")
        ?? "Data Source=ocpp.db"
    ));

builder.Services.AddSingleton<TransactionIdService>();

builder.Services.AddSignalR(opts =>
{
    opts.EnableDetailedErrors = builder.Environment.IsDevelopment();
    opts.MaximumReceiveMessageSize = 64 * 1024; // 64 KB
});

builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.ReferenceHandler =
            System.Text.Json.Serialization.ReferenceHandler.IgnoreCycles;
        options.JsonSerializerOptions.DefaultIgnoreCondition =
            System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull;
    });
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new() { Title = "OCPP 1.6 Backend", Version = "v1" });
});

// Allow Flutter apps (any origin in dev — tighten in production)
builder.Services.AddCors(opts =>
{
    opts.AddDefaultPolicy(policy =>
    {
        policy
            .AllowAnyHeader()
            .AllowAnyMethod()
            .AllowCredentials()
            .SetIsOriginAllowed(_ => true); // tighten for production
    });
});

var app = builder.Build();

Console.WriteLine(app.Environment.EnvironmentName);

// ─── Middleware ────────────────────────────────────────────────────────────────

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors();

// WebSocket support is required for SignalR long-polling and WS transports
app.UseWebSockets(new WebSocketOptions
{
    KeepAliveInterval = TimeSpan.FromSeconds(30)
});

app.UseRouting();
app.MapControllers();
app.MapHub<OcppHub>("/ocpp");

// ─── DB Init ──────────────────────────────────────────────────────────────────
await DbInitializer.InitializeAsync(app.Services);

app.Logger.LogInformation("OCPP Backend started.");
app.Logger.LogInformation("SignalR Hub:  ws://localhost:5000/ocpp");
app.Logger.LogInformation("Swagger UI:   http://localhost:5000/swagger");

app.Run();
