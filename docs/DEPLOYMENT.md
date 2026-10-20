# Self-hosting

## Bật/tắt QChat trên VPS

Sau khi SSH vào VPS, chạy `cd /opt/qchat` trước các lệnh dưới đây.
Các lệnh chỉ quản lý stack QChat, không tắt Nginx Proxy Manager hoặc các app khác.

```sh
cd /opt/qchat

# Bật QChat bằng image đã build
docker compose --env-file .env -f infra/compose.vps.yaml up -d --no-build

# Tắt QChat, giữ nguyên container và dữ liệu
docker compose --env-file .env -f infra/compose.vps.yaml stop

# Khởi động lại riêng API và realtime
docker compose --env-file .env -f infra/compose.vps.yaml restart server realtime

# Xem trạng thái
docker compose --env-file .env -f infra/compose.vps.yaml ps -a

# Xem log trực tiếp; Ctrl+C chỉ thoát xem log, không tắt server
docker compose --env-file .env -f infra/compose.vps.yaml logs --tail=100 -f server realtime

# Kiểm tra API qua HTTPS
curl --fail https://chat.nguyenphuquyet.online/api/health
```

`server`, `realtime`, `postgres`, `redis`, `storage`, `gateway` là các dịch vụ
chạy thường trực. `migrate` và `storage-init` hiện `Exited (0)` sau khi hoàn thành
là bình thường. Khi tắt QChat, domain có thể trả lỗi 502 qua proxy.

Không dùng `down -v`: tùy chọn `-v` xóa các volume chứa database và file.
`restart` không nạp lại thay đổi trong `.env`. Sau khi sửa biến môi trường của
API/realtime, dùng:

```sh
docker compose --env-file .env -f infra/compose.vps.yaml up -d --no-build --no-deps --force-recreate server realtime
```

Lệnh trên không đổi mật khẩu PostgreSQL hay thông tin kho file đã khởi tạo;
việc đổi các thông tin đó cần quy trình riêng. Thay đổi mã nguồn cần build image
mới theo hướng dẫn cập nhật bên dưới.

## VPS behind Nginx Proxy Manager

The VPS deployment uses `/opt/qchat`, `infra/compose.vps.yaml` and a private
`.env` (mode 600) generated on the server. It does not require another TLS proxy.
Nginx Proxy Manager forwards `chat.nguyenphuquyet.online` to HTTP
`172.17.0.1:3210`, with WebSocket support and the existing certificate enabled.
Port 3210 binds only to the Docker bridge address. PostgreSQL, Redis and S3 ports
are not published. The existing MySQL and other applications are independent.

The VPS configuration uses RustFS 1.0.3 for private S3 storage, because the legacy
MinIO image in the original example is no longer downloadable. The storage-init
job creates the private `qchat-private` bucket and its CORS configuration. Keep
`S3_ENDPOINT=https://chat.nguyenphuquyet.online`; the gateway forwards bucket paths
without rewriting their signed Host or URI. The storage console is disabled.

```sh
cd /opt/qchat
docker compose --env-file .env -f infra/compose.vps.yaml build server
docker compose --env-file .env -f infra/compose.vps.yaml up -d --no-build
docker compose --env-file .env -f infra/compose.vps.yaml ps -a
curl --fail https://chat.nguyenphuquyet.online/api/health
# Real end-to-end verification; creates and removes its own temporary records:
docker compose --env-file .env -f infra/compose.vps.yaml exec -T server node --input-type=module < infra/smoke-test.mjs
```

Configure SMTP in `/opt/qchat/.env` and recreate the backend services to enable
verification and password-reset email. No SMTP credentials are included in Git.
For updates, back up PostgreSQL and the `qchat_media` volume first, pull the reviewed
commit, set a new `QCHAT_VERSION` image tag in `.env`, then build and run the commands
above. Never use `down -v` on this deployment. If a migration is incompatible with
the old application, rollback requires a matching database backup as well as the
previous image.

## Original standalone TLS example

1. Install Docker Engine and Compose on a Linux VPS. Configure DNS names for API/realtime and private media. Restrict database, Redis, MinIO console and service ports to the Docker network.
2. Copy `.env.example` to `.env`. Generate independent random database, storage and JWT secrets. Set the real API web origin and S3 endpoint. Never commit `.env`.
3. Put a certificate covering both names and its private key at `infra/certs/fullchain.pem` and `infra/certs/privkey.pem`. Update the two nginx server names. Configure certificate renewal outside the container.
4. Run `docker compose --env-file .env -f infra/compose.yaml up --build -d`. The migration job must complete before server/gateway start.
5. Create `qchat-private` in MinIO using an administrative client on the private network. Keep the bucket private. Configure bucket CORS for the exact Flutter web origin, with PUT/GET/HEAD and Content-Type allowed. The same S3 endpoint must be reachable from browsers and containers so signatures match.
6. Configure SMTP credentials for verification/reset. The server returns EMAIL_NOT_CONFIGURED when no provider exists; it never fakes delivery.
7. Build Flutter with `--dart-define=API_URL=https://chat.example.com/api --dart-define=REALTIME_URL=https://chat.example.com`. Web media and camera require HTTPS except localhost.
8. The admin console is at `/admin` on the Next.js service. Promote a specific existing user to ADMIN through an audited operational database procedure; there is no default admin or shared password.

The current Compose deployment has not been executed in this Windows environment. The admin UI is served by the main Next.js application to share authorization and avoid an additional public origin. TURN, push, background calling and media scanning require further implementation/configuration before production.

## Backup and restore

Take encrypted PostgreSQL dumps with `docker compose -f infra/compose.yaml exec -T postgres pg_dump -U qchat -Fc qchat > qchat.dump`. Back up the private MinIO bucket with an S3-compatible backup client and retain its encryption/access configuration. Store backups off-host with restricted access. Redis holds transient coordination; its loss must not delete messages.

Restore to an isolated environment first using `pg_restore --clean --if-exists --no-owner`, restore media objects with unchanged keys, and validate counts and account/message access before switching DNS. Revoke sessions and rotate secrets if the backup was exposed. Practice restore drills; backups are not verified until restored.

## Retention

The current account-delete endpoint disables the account and revokes sessions; it does not purge all personal data. Export currently caps each collection at 1,000 records. A complete retention/export/purge job and legal policy are release blockers. No production retention promise is made by this baseline.
