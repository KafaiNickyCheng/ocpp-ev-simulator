using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

#pragma warning disable CA1814 // Prefer jagged arrays over multidimensional

namespace OcppBackend.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "ChargePoints",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    ChargePointId = table.Column<string>(type: "TEXT", maxLength: 50, nullable: false),
                    Vendor = table.Column<string>(type: "TEXT", nullable: false),
                    Model = table.Column<string>(type: "TEXT", nullable: false),
                    SerialNumber = table.Column<string>(type: "TEXT", nullable: false),
                    FirmwareVersion = table.Column<string>(type: "TEXT", nullable: false),
                    IsOnline = table.Column<bool>(type: "INTEGER", nullable: false),
                    LastHeartbeat = table.Column<DateTime>(type: "TEXT", nullable: true),
                    LastBootTime = table.Column<DateTime>(type: "TEXT", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ChargePoints", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "IdTags",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    TagId = table.Column<string>(type: "TEXT", maxLength: 20, nullable: false),
                    UserId = table.Column<string>(type: "TEXT", nullable: true),
                    UserName = table.Column<string>(type: "TEXT", nullable: true),
                    Status = table.Column<string>(type: "TEXT", nullable: false),
                    ExpiryDate = table.Column<DateTime>(type: "TEXT", nullable: true),
                    ParentTagId = table.Column<string>(type: "TEXT", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    Note = table.Column<string>(type: "TEXT", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_IdTags", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "MessageLogs",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    ChargePointId = table.Column<string>(type: "TEXT", nullable: false),
                    Direction = table.Column<string>(type: "TEXT", nullable: false),
                    Action = table.Column<string>(type: "TEXT", nullable: false),
                    MessageId = table.Column<string>(type: "TEXT", nullable: false),
                    Payload = table.Column<string>(type: "TEXT", nullable: false),
                    IsError = table.Column<bool>(type: "INTEGER", nullable: false),
                    Timestamp = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_MessageLogs", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Connectors",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    ChargePointId = table.Column<int>(type: "INTEGER", nullable: false),
                    ConnectorId = table.Column<int>(type: "INTEGER", nullable: false),
                    Status = table.Column<string>(type: "TEXT", nullable: false),
                    ErrorCode = table.Column<string>(type: "TEXT", nullable: false),
                    ErrorInfo = table.Column<string>(type: "TEXT", nullable: true),
                    StatusTimestamp = table.Column<DateTime>(type: "TEXT", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Connectors", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Connectors_ChargePoints_ChargePointId",
                        column: x => x.ChargePointId,
                        principalTable: "ChargePoints",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "Transactions",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    TransactionId = table.Column<int>(type: "INTEGER", nullable: false),
                    ChargePointId = table.Column<int>(type: "INTEGER", nullable: false),
                    ConnectorId = table.Column<int>(type: "INTEGER", nullable: false),
                    ConnectorNumber = table.Column<int>(type: "INTEGER", nullable: false),
                    IdTag = table.Column<string>(type: "TEXT", nullable: false),
                    Status = table.Column<string>(type: "TEXT", nullable: false),
                    MeterStart = table.Column<int>(type: "INTEGER", nullable: false),
                    MeterStop = table.Column<int>(type: "INTEGER", nullable: true),
                    StartTime = table.Column<DateTime>(type: "TEXT", nullable: false),
                    StopTime = table.Column<DateTime>(type: "TEXT", nullable: true),
                    StopReason = table.Column<string>(type: "TEXT", nullable: true),
                    EnergyDeliveredKwh = table.Column<double>(type: "REAL", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Transactions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Transactions_ChargePoints_ChargePointId",
                        column: x => x.ChargePointId,
                        principalTable: "ChargePoints",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_Transactions_Connectors_ConnectorId",
                        column: x => x.ConnectorId,
                        principalTable: "Connectors",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "MeterValues",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    TransactionId = table.Column<int>(type: "INTEGER", nullable: false),
                    Timestamp = table.Column<DateTime>(type: "TEXT", nullable: false),
                    EnergyWh = table.Column<double>(type: "REAL", nullable: true),
                    PowerW = table.Column<double>(type: "REAL", nullable: true),
                    VoltageV = table.Column<double>(type: "REAL", nullable: true),
                    CurrentA = table.Column<double>(type: "REAL", nullable: true),
                    Context = table.Column<string>(type: "TEXT", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_MeterValues", x => x.Id);
                    table.ForeignKey(
                        name: "FK_MeterValues_Transactions_TransactionId",
                        column: x => x.TransactionId,
                        principalTable: "Transactions",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.InsertData(
                table: "IdTags",
                columns: new[] { "Id", "CreatedAt", "ExpiryDate", "Note", "ParentTagId", "Status", "TagId", "UserId", "UserName" },
                values: new object[,]
                {
                    { 1, new DateTime(2024, 1, 1, 0, 0, 0, 0, DateTimeKind.Utc), null, null, null, "Accepted", "TAG-001", null, "Alice" },
                    { 2, new DateTime(2024, 1, 1, 0, 0, 0, 0, DateTimeKind.Utc), null, null, null, "Accepted", "TAG-002", null, "Bob" },
                    { 3, new DateTime(2024, 1, 1, 0, 0, 0, 0, DateTimeKind.Utc), null, null, null, "Accepted", "TAG-003", null, "Carol" },
                    { 4, new DateTime(2024, 1, 1, 0, 0, 0, 0, DateTimeKind.Utc), null, null, null, "Accepted", "RFID-ADMIN", null, "Admin" },
                    { 5, new DateTime(2024, 1, 1, 0, 0, 0, 0, DateTimeKind.Utc), null, null, null, "Accepted", "RFID-USER1", null, "User1" },
                    { 6, new DateTime(2024, 1, 1, 0, 0, 0, 0, DateTimeKind.Utc), null, null, null, "Accepted", "RFID-USER2", null, "User2" },
                    { 7, new DateTime(2024, 1, 1, 0, 0, 0, 0, DateTimeKind.Utc), null, null, null, "Accepted", "REMOTE-TAG", null, "Remote" }
                });

            migrationBuilder.CreateIndex(
                name: "IX_ChargePoints_ChargePointId",
                table: "ChargePoints",
                column: "ChargePointId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Connectors_ChargePointId_ConnectorId",
                table: "Connectors",
                columns: new[] { "ChargePointId", "ConnectorId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_IdTags_TagId",
                table: "IdTags",
                column: "TagId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_MessageLogs_ChargePointId",
                table: "MessageLogs",
                column: "ChargePointId");

            migrationBuilder.CreateIndex(
                name: "IX_MessageLogs_Timestamp",
                table: "MessageLogs",
                column: "Timestamp");

            migrationBuilder.CreateIndex(
                name: "IX_MeterValues_TransactionId",
                table: "MeterValues",
                column: "TransactionId");

            migrationBuilder.CreateIndex(
                name: "IX_Transactions_ChargePointId",
                table: "Transactions",
                column: "ChargePointId");

            migrationBuilder.CreateIndex(
                name: "IX_Transactions_ConnectorId",
                table: "Transactions",
                column: "ConnectorId");

            migrationBuilder.CreateIndex(
                name: "IX_Transactions_TransactionId",
                table: "Transactions",
                column: "TransactionId",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "IdTags");

            migrationBuilder.DropTable(
                name: "MessageLogs");

            migrationBuilder.DropTable(
                name: "MeterValues");

            migrationBuilder.DropTable(
                name: "Transactions");

            migrationBuilder.DropTable(
                name: "Connectors");

            migrationBuilder.DropTable(
                name: "ChargePoints");
        }
    }
}
