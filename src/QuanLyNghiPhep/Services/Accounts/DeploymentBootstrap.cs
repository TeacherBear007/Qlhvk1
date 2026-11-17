using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Identity;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using QuanLyNghiPhep.Data;

namespace QuanLyNghiPhep.Services.Accounts;

/// <summary>Đổi mật khẩu tài khoản nhập từ localhost đúng một lần; giữ tên và dữ liệu nghiệp vụ.</summary>
public static class DeploymentBootstrap
{
    private const string Marker = "qlhvk1-passwords-v1";

    public static void CheckData(string directory, bool requireMarker)
    {
        foreach (var name in new[] { "accounts.db", "business.db" })
            if (!File.Exists(Path.Combine(directory, name)) || new FileInfo(Path.Combine(directory, name)).Length == 0)
                throw new InvalidOperationException($"Thiếu AppData/{name}. Dừng để tránh khởi tạo mất dữ liệu localhost.");
        using var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = Path.Combine(directory, "accounts.db"), Mode = SqliteOpenMode.ReadOnly
        }.ToString());
        connection.Open();
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT COUNT(*) FROM AspNetUsers";
        if (Convert.ToInt64(command.ExecuteScalar()) == 0)
            throw new InvalidOperationException("Database nhập từ localhost không có tài khoản. Không tự tạo lại trên server.");
        if (!requireMarker) return;
        command.CommandText = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='DeploymentBootstrap'";
        if (Convert.ToInt64(command.ExecuteScalar()) != 0)
        {
            command.CommandText = "SELECT COUNT(*) FROM DeploymentBootstrap WHERE Id=$id";
            command.Parameters.AddWithValue("$id", Marker);
            if (Convert.ToInt64(command.ExecuteScalar()) == 1) return;
        }
        throw new InvalidOperationException("AppData chưa được khởi tạo cho server. Chạy quy trình deploy để đổi mật khẩu lần đầu.");
    }

    public static async Task InitializeAsync(IServiceProvider services, string directory)
    {
        CheckData(directory, requireMarker: false);
        using var scope = services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
        var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
        var protector = scope.ServiceProvider.GetRequiredService<IDataProtectionProvider>()
            .CreateProtector("QLHVK1.DeploymentCredentials.v1");
        await db.Database.ExecuteSqlRawAsync("""
            CREATE TABLE IF NOT EXISTS DeploymentBootstrap (
                Id TEXT PRIMARY KEY, CreatedUtc TEXT NOT NULL, CredentialsProtected TEXT NOT NULL)
            """);
        // Reset và dấu hoàn thành cùng transaction: bị ngắt thì rollback toàn bộ.
        await using var transaction = await db.Database.BeginTransactionAsync();
        using var command = db.Database.GetDbConnection().CreateCommand();
        command.Transaction = transaction.GetDbTransaction();
        command.CommandText = "SELECT CredentialsProtected FROM DeploymentBootstrap WHERE Id=$id";
        var parameter = command.CreateParameter();
        parameter.ParameterName = "$id";
        parameter.Value = Marker;
        command.Parameters.Add(parameter);
        var saved = await command.ExecuteScalarAsync() as string;
        string credentials;
        if (saved is not null)
        {
            credentials = protector.Unprotect(saved);
        }
        else
        {
            var accounts = await users.Users.OrderBy(user => user.UserName).ToListAsync();
            var lines = new List<string> { "Tên đăng nhập\tVai trò\tMật khẩu lúc triển khai đầu", "Giữ riêng tệp này. Không đưa lên GitHub hoặc log Actions." };
            foreach (var user in accounts)
            {
                var password = AccountSetup.NewPassword();
                // UserManager gọi RecoverablePasswordHasher để băm trước khi lưu vào SQLite.
                // Giữ cơ chế bản mã riêng để Admin xem mật khẩu của ứng dụng gốc.
                AccountSetup.Check(await users.ResetPasswordAsync(user,
                    await users.GeneratePasswordResetTokenAsync(user), password));
                user.LockoutEnd = null;
                user.AccessFailedCount = 0;
                AccountSetup.Check(await users.UpdateAsync(user));
                lines.Add($"{user.UserName}\t{string.Join(",", await users.GetRolesAsync(user))}\t{password}");
            }
            credentials = string.Join(Environment.NewLine, lines) + Environment.NewLine;
            command.CommandText = "INSERT INTO DeploymentBootstrap (Id,CreatedUtc,CredentialsProtected) VALUES ($id,$time,$credentials)";
            var time = command.CreateParameter();
            time.ParameterName = "$time";
            time.Value = DateTimeOffset.UtcNow.ToString("O");
            command.Parameters.Add(time);
            var encrypted = command.CreateParameter();
            encrypted.ParameterName = "$credentials";
            encrypted.Value = protector.Protect(credentials);
            command.Parameters.Add(encrypted);
            await command.ExecuteNonQueryAsync();
        }
        await transaction.CommitAsync();
        // Nếu lần trước dừng sau commit, khôi phục tệp từ bản mã mà không sinh mật khẩu khác.
        var path = Path.Combine(directory, "tai-khoan-server.txt");
        if (saved is null || !File.Exists(path))
        {
            var temporary = path + ".tmp";
            var fileOptions = new FileStreamOptions { Mode = FileMode.Create, Access = FileAccess.Write };
            if (!OperatingSystem.IsWindows())
                fileOptions.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
            await using (var output = new FileStream(temporary, fileOptions))
            await using (var writer = new StreamWriter(output))
                await writer.WriteAsync(credentials);
            File.Move(temporary, path, overwrite: true);
            if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite);
        }
        Console.WriteLine(saved is null
            ? "Đã đổi mật khẩu tất cả tài khoản một lần. Xem AppData/tai-khoan-server.txt trực tiếp trên server."
            : "Đã khởi tạo trước đó: giữ nguyên tên đăng nhập, mật khẩu và dữ liệu hiện tại.");
    }
}
