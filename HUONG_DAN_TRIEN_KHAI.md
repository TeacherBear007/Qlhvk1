# Triển khai QLHVK1 qua GitHub Actions

Bản này dành cho server đã có Docker, Docker Compose v2, Nginx, Certbot với plugin nginx,
Python 3, OpenSSL và SSH root. Workflow chỉ triển khai, không cài lại công cụ.
Nhánh triển khai là **main**. Domain đã cấu hình: **qlhvk1.hoanganhplus01.io.vn**.

## 1. Đưa đúng phần dự án lên repo công khai

Đưa **nội dung REPO_UPLOAD** vào gốc repo. Ví dụ gốc repo phải có Dockerfile,
docker-compose.yml, src/, deploy/, .github/, README.md.

**Không upload KHONG_UPLOAD, AppData_localhost hoặc INITIAL_DATA_KEY.txt.**
Không upload nguyên ZIP này lên GitHub. Các file bắt đầu bằng dấu chấm cũng cần được commit,
đặc biệt .github/workflows/deploy.yml. Nếu upload qua trình duyệt không đưa được thư mục .github,
dùng Git/GitHub Desktop hoặc tạo file đó đúng đường dẫn trên GitHub.

Bản dữ liệu nằm trong deploy/seed/appdata.tar.gz.enc, đã mã hóa bằng AES-256-CBC với
PBKDF2 200.000 vòng và khóa ngẫu nhiên lưu riêng. Hash của archive được kiểm tra sau giải mã.
Dữ liệu thật, keys và mật khẩu không nằm dạng đọc trực tiếp trong repo.

## 2. GitHub Secrets

Vào Settings → Secrets and variables → Actions → New repository secret.

| Secret | Giá trị cần điền |
|---|---|
| SSH_HOST | IP hoặc hostname của server, không có https:// và không có :port |
| SSH_PORT | Cổng SSH; bỏ qua nếu dùng 22 |
| SSH_PRIVATE_KEY | Toàn bộ private key SSH, gồm BEGIN/END, dùng được không cần nhập passphrase trên runner |
| SSH_KNOWN_HOSTS | Dòng host key của chính server, lấy từ nguồn tin cậy; không phải private key |
| INITIAL_DATA_KEY | Một dòng trong KHONG_UPLOAD/INITIAL_DATA_KEY.txt, không thêm dấu nháy |

SSH dùng tài khoản **root**, không cần secret SSH_USER.
Public key tương ứng với SSH_PRIVATE_KEY phải có trong /root/.ssh/authorized_keys trên server.
Không đưa các secret vào YAML hay README.

Để lập SSH_KNOWN_HOSTS, trên phiên root tin cậy có thể đọc public host key:

```bash
cat /etc/ssh/ssh_host_ed25519_key.pub
```

Ghép thành một dòng, thay địa chỉ bằng đúng SSH_HOST:

```text
IP_HOAC_HOST_SERVER ssh-ed25519 NOI_DUNG_PUBLIC_KEY
```

Nếu cổng không phải 22, dùng dạng:

```text
[IP_HOAC_HOST_SERVER]:2222 ssh-ed25519 NOI_DUNG_PUBLIC_KEY
```

Không dùng nội dung /etc/ssh/ssh_host_ed25519_key (đó là private key).
INITIAL_DATA_KEY chỉ cần để nhập dữ liệu lần đầu. Nếu server đã có AppData hợp lệ,
deploy tiếp không cần giải mã lại. Giữ khóa riêng để có thể triển khai lại trên máy mới.

## 3. Chạy deploy

Commit/push lên main. Vào Actions → Deploy QLHVK1 để theo dõi.
Có thể chọn Run workflow trên main để triển khai lại.

Job **changes** chạy trên GitHub, chưa SSH. Nó so với commit của workflow thành công gần nhất,
nên lần triển khai bị lỗi sẽ không khiến commit kế tiếp bỏ sót thay đổi.

| Thay đổi | Hành động |
|---|---|
| src/, Dockerfile hoặc script deploy | Build image trên server rồi cập nhật ứng dụng |
| docker-compose.yml | Cập nhật Compose và chạy lại service, dùng image hiện có nếu code không đổi |
| deploy/nginx/k1qlhv.conf | Cập nhật site Nginx, kiểm tra, reload và để Certbot cấu hình HTTPS |
| Chỉ tài liệu | Bỏ qua job SSH deploy |
| Lần đầu hoặc chạy tay | Triển khai ứng dụng; Nginx/Compose vẫn chỉ ghi lại nếu thiếu hoặc thực sự thay đổi |

Script trên server còn so nội dung Compose và hash template Nginx với trạng thái thành công đã lưu.
Không thay site Nginx chỉ vì app có commit mới; cấu hình HTTPS do Certbot thêm được giữ nguyên.

Workflow chuyển source qua SSH, build tại server, không dùng registry và không có job CI build/test.
Không có bước cài đặt Docker, Nginx hoặc Certbot.

## 4. Dữ liệu localhost được giữ thế nào?

“Database chưa có người dùng” nghĩa là **bảng AspNetUsers trong accounts.db không có tài khoản**.
Điều đó không tự động có nghĩa bảng học viên hoặc phiếu trong business.db cũng trống.

ZIP gốc có 6 tài khoản, 51 học viên và 47 phiếu. Bản chuyển server được tạo bằng SQLite backup API,
đọc cả giao dịch đã commit nằm trong accounts.db-wal. Vì vậy không chỉ copy mỗi file .db và bỏ mất WAL.
Các bảng khác, thông tin liên kết, JSON, keys và backup cũng được giữ.

Lần triển khai đầu:

1. Build image.
2. Nếu /var/lib/qlhvk1/AppData chưa có dữ liệu, giải mã vào thư mục tạm.
3. Kiểm tra hash archive, SQLite integrity_check và số bản ghi của từng bảng.
4. Chuyển cả thư mục vào vị trí chính thức sau khi kiểm tra thành công.
5. Sao lưu và chạy bước đổi mật khẩu một lần, rồi bật ứng dụng.

Các lần sau:

- Không chép seed đè lên AppData hiện có, kể cả khi seed trong repo thay đổi.
- Dừng ứng dụng trước khi chụp bản sao lưu, sau đó thay container/image.
- Bind mount nối /var/lib/qlhvk1/AppData với /app/AppData trong container.
- Nếu AppData có sẵn nhưng thiếu database, script dừng để kiểm tra, không tự “sửa” bằng dữ liệu mẫu.
- Nếu mount thiếu dữ liệu khi chạy production, app dừng thay vì tạo database trắng.

| Vị trí trên server | Ý nghĩa |
|---|---|
| /opt/qlhvk1/releases/ | Source theo từng lần deploy |
| /opt/qlhvk1/current | Symlink đến source của image đang dùng |
| /opt/qlhvk1/docker-compose.yml | Cấu hình Compose đã triển khai |
| /opt/qlhvk1/.env | Tag image và đường dẫn build hiện tại, không chứa khóa nhập dữ liệu |
| /var/lib/qlhvk1/AppData | Dữ liệu đang sử dụng, độc lập với thư mục source và container |
| /var/backups/qlhvk1/ | Bản sao AppData trước mỗi lần thay ứng dụng/Compose |

Đây là cơ chế giữ dữ liệu qua deploy và có bản sao lưu, không phải bảo đảm trước mọi sự cố ổ đĩa.
Không xóa /var/lib/qlhvk1/AppData khi cập nhật code. Sao lưu cả thư mục, gồm keys và hai database.
Nếu cần khôi phục, ưu tiên bản AppData-before-... của server đã khởi tạo; khôi phục khi app đã dừng.
Không tự ghi đè dữ liệu hiện tại chỉ để xử lý lỗi deploy.

Nếu deploy lỗi sau khi đã dừng app, script thử chạy lại image/Compose cũ và giữ nguyên AppData.
Lần đầu lỗi vẫn giữ AppData đã nhập để lần chạy sau tiếp tục, không sinh bộ dữ liệu khác.

## 5. Tên đăng nhập, mật khẩu và hàm băm

Tên đăng nhập, ID tài khoản, quyền, hồ sơ và các liên kết được giữ.
Lần deploy đầu dùng AccountSetup.NewPassword() để sinh mật khẩu ngẫu nhiên cho **tất cả tài khoản**.

Phần mới là **gọi chức năng sinh mật khẩu để đổi các tài khoản đã có đúng một lần**.
Hàm khởi tạo cũ chỉ sinh mật khẩu cho tài khoản mới hoặc Admin bổ sung;
nó không tự đổi mật khẩu những tài khoản được chuyển từ localhost.

ASP.NET Core Identity trong C# thực hiện băm qua UserManager/PasswordHasher,
rồi lưu hash vào accounts.db. **Không cần viết hàm SQL băm mật khẩu.**
Cơ chế riêng hiện có của dự án vẫn lưu thêm bản mã bằng DataProtection để Admin xem mật khẩu;
keys được giữ trong AppData/keys.

Dấu hoàn tất nằm trong bảng DeploymentBootstrap của accounts.db, cùng transaction với việc đổi mật khẩu.
Nếu gặp lỗi giữa chừng, mọi lần đổi trong transaction bị rollback.
Chạy deploy lại thấy dấu hoàn tất sẽ giữ mật khẩu hiện tại, kể cả mật khẩu được người dùng đổi sau đó.

Đọc mật khẩu lần đầu bằng phiên SSH riêng:

```bash
cat /var/lib/qlhvk1/AppData/tai-khoan-server.txt
```

File có quyền 0600, nằm trong thư mục riêng. Workflow không in mật khẩu lên log Actions.
File ghi mật khẩu tại thời điểm deploy đầu, không phải danh sách luôn cập nhật sau các lần đổi thủ công.
Không upload hoặc chụp công khai file này.

## 6. Nginx, WebSocket và Certbot

- Nginx trên host chuyển request vào http://127.0.0.1:8989.
- App cũng nghe cổng 8989 trong container; cổng host chỉ bind loopback.
- Template repo: deploy/nginx/k1qlhv.conf.
- Site server: /etc/nginx/sites-available/k1qlhv.
- Symlink: /etc/nginx/sites-enabled/k1qlhv.
- Template có HTTP/1.1, Upgrade và Connection để Blazor/SignalR dùng WebSocket.
- Template không có ssl_certificate hoặc ssl_certificate_key. Certbot tự thêm.
- Email Certbot: anhoanganh7777@gmail.com.
- DNS phải trỏ đúng server và cổng 80/443 phải truy cập được từ Internet.

Khi đổi template, script giữ bản cấu hình cũ, chạy nginx -t, reload và gọi Certbot
với --keep-until-expiring để dùng lại chứng chỉ còn hạn. Nếu lỗi, script khôi phục site cũ.
Những lần chỉ đổi app không chép template HTTP đè lên site HTTPS.

Gateway Docker là 172.28.89.1 (subnet 172.28.89.0/24).
Program.cs tin X-Forwarded-Proto/X-Forwarded-For từ proxy này để tránh redirect lặp
và dùng cookie HTTPS đúng sau Nginx. Nếu đổi subnet, phải đổi gateway và
Deployment__NginxProxyIp trong Compose cùng nhau.

## 7. Kiểm tra sau deploy

```bash
cd /opt/qlhvk1
docker compose ps
curl -fsS http://127.0.0.1:8989/health
nginx -t
readlink -f /etc/nginx/sites-enabled/k1qlhv
```

Mở https://qlhvk1.hoanganhplus01.io.vn, đăng nhập bằng mật khẩu server vừa sinh.
Kiểm tra danh sách học viên/phiếu. Chỉnh thử một bản ghi, deploy lại và kiểm tra bản ghi vẫn còn.
Trong DevTools → Network → WS, kết nối /_blazor phải nâng cấp thành WebSocket.

## 8. Chạy lại trên localhost

Nếu muốn mở cùng bộ dữ liệu gốc bằng Visual Studio, khi ứng dụng đã tắt,
copy **toàn bộ nội dung KHONG_UPLOAD/AppData_localhost** vào
REPO_UPLOAD/src/QuanLyNghiPhep/AppData (chỉ làm với thư mục đích mới/rỗng).
Giữ cả các file -wal, -shm và keys. Sau đó mở solution như trước.

Ở localhost không đặt Deployment__RequireInitializedData=true và không chạy
--deployment-initialize. Tài khoản/mật khẩu localhost giữ nguyên.
Thư mục AppData phải tiếp tục được giữ riêng khi upload repo công khai.

## 9. Các file thay đổi

- Dockerfile, docker-compose.yml, .dockerignore, .gitignore.
- .github/workflows/deploy.yml: kiểm tra thay đổi và CD.
- deploy/nginx/k1qlhv.conf, deploy/scripts/: nhập dữ liệu, deploy, cập nhật Nginx.
- deploy/seed/: bản AppData mã hóa và checksum.
- Program.cs: trusted proxy, healthcheck và chặn chạy production khi dữ liệu chưa sẵn sàng.
- Services/Accounts/DeploymentBootstrap.cs: đổi mật khẩu đúng một lần.
- Tài liệu triển khai này và phần chỉ dẫn trong README.

## 10. Tài liệu kỹ thuật đối chiếu

- https://nginx.org/en/docs/http/websocket.html
- https://learn.microsoft.com/en-us/aspnet/core/breaking-changes/8/forwarded-headers-unknown-proxies
- https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/pass-job-outputs
- https://eff-certbot.readthedocs.io/en/stable/man/certbot.html
