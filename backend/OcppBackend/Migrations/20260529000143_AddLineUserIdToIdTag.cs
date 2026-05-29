using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace OcppBackend.Migrations
{
    /// <inheritdoc />
    public partial class AddLineUserIdToIdTag : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "LineUserId",
                table: "IdTags",
                type: "TEXT",
                nullable: true);

            migrationBuilder.UpdateData(
                table: "IdTags",
                keyColumn: "Id",
                keyValue: 1,
                column: "LineUserId",
                value: null);

            migrationBuilder.UpdateData(
                table: "IdTags",
                keyColumn: "Id",
                keyValue: 2,
                column: "LineUserId",
                value: null);

            migrationBuilder.UpdateData(
                table: "IdTags",
                keyColumn: "Id",
                keyValue: 3,
                column: "LineUserId",
                value: null);

            migrationBuilder.UpdateData(
                table: "IdTags",
                keyColumn: "Id",
                keyValue: 4,
                column: "LineUserId",
                value: null);

            migrationBuilder.UpdateData(
                table: "IdTags",
                keyColumn: "Id",
                keyValue: 5,
                column: "LineUserId",
                value: null);

            migrationBuilder.UpdateData(
                table: "IdTags",
                keyColumn: "Id",
                keyValue: 6,
                column: "LineUserId",
                value: null);

            migrationBuilder.UpdateData(
                table: "IdTags",
                keyColumn: "Id",
                keyValue: 7,
                column: "LineUserId",
                value: null);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "LineUserId",
                table: "IdTags");
        }
    }
}
