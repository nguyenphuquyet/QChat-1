# QChat

Flutter + TDesign messaging application with a Next.js REST backend, PostgreSQL/Prisma, Redis, a standalone Socket.IO gateway, and private S3/MinIO media. Source is implemented in this workspace; no fake chat API or seeded user conversations are used.

**Status: incomplete, not production-ready.** Read [implementation and verification status](docs/STATUS.md) before deployment.

## Requirements

- Node.js 24 and pnpm 10.11.0
- Flutter 3.47.7 / Dart 3.13.5 (resolved package versions in `apps/mobile/pubspec.lock`)
- PostgreSQL 17, Redis 7, private S3-compatible storage
- Android SDK/JDK for APK builds; macOS/Xcode for iOS

## Backend

```sh
pnpm install --frozen-lockfile
pnpm db:generate
# Set DATABASE_URL, REDIS_URL, JWT_SECRET and WEB_ORIGIN in the process environment.
pnpm db:migrate
pnpm --filter @qchat/server dev
pnpm --filter @qchat/realtime dev
```

For local Flutter web, use `WEB_ORIGIN=http://localhost:8080`. The REST base is `http://localhost:3000/api` and realtime is `http://localhost:3001`. Production requires HTTPS/WSS. See [deployment](docs/DEPLOYMENT.md) for Docker Compose and backups.

## Flutter on Chrome

```sh
cd apps/mobile
flutter pub get --enforce-lockfile
flutter run -d chrome --web-port 8080 --dart-define=API_URL=http://localhost:3000/api --dart-define=REALTIME_URL=http://localhost:3001
```

Or build and serve the release bundle:

```sh
cd apps/mobile
flutter build web --release
cd ../..
node scripts/serve-web.mjs
```

Open `http://localhost:8080` in Chrome. Dependencies and SDK are installed locally under `.tools/flutter` in this workspace. The Windows SDK path contains spaces, which currently triggers a native-hook tool error; a temporary `subst Q: "E:\Qchat APP"` alias allows invoking `Q:\.tools\flutter\bin\flutter.bat` from a path without spaces. The alias does not move files.

Register two real accounts, send and accept a friend request, then open the friend from Contacts. Verify text delivery with two browser profiles or separate devices; browsers sharing one origin/profile also share secure storage and should not be used as independent accounts.

## Automatic builds (GitHub Actions)

Two independent workflows run on pushes to `main`, pull requests that change their
respective paths, or manually from **Actions → Run workflow**:

- **Flutter app** (`.github/workflows/flutter.yml`): Flutter 3.47.7, dependency lock
  verification, analysis and tests, then separate Android APK, web and unsigned iOS builds.
  Download `qchat-android-<commit>`, `qchat-web-<commit>` and
  `qchat-ios-unsigned-<commit>` from the run's Artifacts.
  The macOS job builds with `flutter build ios --release --no-codesign` and packages
  `Payload/Runner.app` as `qchat-unsigned.ipa`. No Apple certificate or provisioning
  profile is required to build; the IPA must be signed before installation on an iPhone.
  Linux runs the UI rendering tests; pixel golden comparisons currently run only on Windows.
- **Server** (`.github/workflows/server.yml`): Node 24 / pnpm 10.11.0, Prisma generation,
  TypeScript checks (including realtime), unit tests, and a Docker build that runs
  the Next.js production build. Download `qchat-server-<commit>` and load its image
  with `docker load -i qchat-server.tar`. The image includes the REST server and
  realtime gateway; its default command starts REST. To start the gateway instead,
  pass `pnpm --filter @qchat/realtime start` as the container command. Supply the
  backend environment and service connections at runtime as with local deployment.

In **Settings → Secrets and variables → Actions → Variables**, set `API_URL`
(including `/api`) and `REALTIME_URL` to your reachable backend URLs before building
the Flutter app for devices. If unset, the app and CI builds use
`https://chat.nguyenphuquyet.online/api` for REST and
`https://chat.nguyenphuquyet.online` for Socket.IO. The reverse proxy must route
`/api` to the REST server and `/socket.io/` to the realtime gateway.
These URLs are compiled into the app; they are not secrets. The Android APK uses
the existing debug signing configuration and is for testing, not Play Store release.
APK/web/IPA artifacts are kept for 14 days; server images for 7 days. No automatic
deployment or live-service integration tests are performed by these workflows.

### Local checks

```sh
pnpm typecheck
pnpm test
pnpm build
# Requires running real backend/gateway/database/Redis:
TEST_API_URL=http://localhost:3000/api TEST_REALTIME_URL=http://localhost:3001 pnpm test:integration
cd apps/mobile
flutter analyze
flutter test
flutter build web --release
```

Integration tests skip explicitly when TEST_API_URL is unset. A skipped test is not a pass.

## Structure

### Offline behavior

After signing in once, the saved account opens immediately on restart. Cached API
responses (including chats, contacts and profile) render first while fresh data is
requested in the background. Saved chat history renders before synchronization.
Connection failures show a non-blocking banner with Retry; the app retries session
recovery every 15 seconds. Home navigation remains available even without cached
data. Cache stays scoped to each account and is cleared on successful logout.
Only content already downloaded is available offline; this does not cache remote
media files or guarantee a first-ever browser page load without internet.

### Directories

- `apps/mobile`: Flutter QChat design system, authentication, chats, contacts, groups, Moments, profile, settings and initial WebRTC client.
- `apps/server`: Next.js API, domain modules, Prisma schema and SQL migration.
- `apps/realtime`: authenticated gateway and transactional outbox delivery.
- `apps/admin`: admin interface served through Next.js `/admin`.
- `packages/contracts`: strict shared Zod schemas.
- `infra`: Dockerfiles, Compose, HTTPS/WSS reverse proxy.
- `tests`: contract/security unit tests and real-service integration scenario.

No end-to-end encryption is claimed. Private message content is stored server-side. Full push/background-call support and several advanced UI flows remain unfinished.
"# Trigger CI" 
