## 0.0.17

- Patch release (same as 0.0.16); republish after release pipeline setup.

## 0.0.16

- Refine the framed live monitor: centered `APP_NAME`, single-line HTTP/queue stats, last **5** traffic rows, last **5** log lines (Log above Exceptions), last **3** exceptions with clickable `.txt` detail paths (OSC-8).
- Write per-exception detail files under `storage/logs/exceptions/<id>.txt` (plus the existing aggregate log).
- When `QUDS_MONITOR=true`, suppress stdout line logs so only the framed panel (or silent buffer) owns output; use `integratedTerminal` in `launch.json` for the panel in VS Code / Cursor.

## 0.0.15

- Live monitor defaults to **on** (`QUDS_MONITOR=true`). Set `QUDS_MONITOR=false` for append-only logs. The framed panel still needs a real TTY (not the IDE Debug Console).
- Local/dev **hot restart** on save (full process respawn). There is no Flutter-style hot reload. `QUDS_HOT_RESTART=false` disables it; skipped under `package:test` and when a debugger is attached.

## 0.0.14

First pub.dev release since **0.0.10**. Includes the 0.0.11–0.0.13 work below (those versions were never published separately).

- Live monitor follows the terminal size, keeps a 200-line log ring (`QUDS_MONITOR_LOG` filter), and shows a queue strip plus **Q** / **WS** pressure bars. Falls back to 76 columns when there is no TTY.
- Queue workers stay single-threaded unless `QUEUE_CONCURRENCY` is set. Optional `QueueInspect`, in-memory `FailedJobLog`, and Insights `GET /quds/insights/failed-jobs`.
- `Mailer.send` hook for verify/reset mail. Existing `EmailAuth.onVerificationToken` / `onResetToken` still run and still work alone.
- Optional `DatabaseUserStore` when `AUTH_USER_STORE=database` (default remains `MemoryUserStore`; custom stores are not replaced).
- Opt-in Prometheus text at `GET /quds/metrics` (`QUDS_METRICS=true`). Optional `QUDS_METRICS_TOKEN`.
- When the live monitor owns stdout, logs also append to `storage/logs/app.log` unless `QUDS_LOG_FILE=false` (or a custom path).

## 0.0.13

- Replace the flickering full-screen monitor wipe with an in-place terminal panel (TTY only; `QUDS_MONITOR=true/false` to force).
- Structured `Log` lines with timestamp, level, and component (`boot`, `http`, `db`, …) for startup and runtime.
- Boot path (env, providers, database, queue, WebSockets, bind) now logs as numbered professional steps instead of emoji `print`s.
- Queue jobs show an in-place preloader (`⠋ JobName`) and settle to ✓ / ✗ with elapsed time.
- Framed terminal logger attaches at boot (alternate screen, coalesced redraws) so logs stay inside the box without flicker.

## 0.0.12

- Add email/password identity (`EmailAuth`) with verification and reset tokens, plus optional `AuthRoutes`.
- Add social login (`SocialAuth`) for Google, Apple, and Firebase on top of the existing JWT pair.
- Add `GcsStorageDisk` and `FILESYSTEM_DISK=gcs` (JSON API, access token or service account).
- Add custom readiness probes (`ReadinessChecker.add`) and transition notifications (`HealthNotifier` / `HEALTH_WEBHOOK_URL`).
- Add Insights HTML dashboard at `GET /quds/insights` (same token gate; `?token=` accepted).

## 0.0.11

### Production lifecycle (defaults unchanged)

- Graceful shutdown on `SIGINT` / `SIGTERM`: drain in-flight requests, stop the queue worker, close WebSockets and providers. Call `QudsServerApp.close()` or send a signal.
- `ServiceProvider.shutdown()` hook (default no-op — existing providers keep compiling).
- Opt-in request limits via `QudsServerApp` fields or env (`MAX_CONCURRENT_REQUESTS`, `REQUEST_TIMEOUT_SECONDS`, `MAX_BODY_BYTES`). `0` keeps unlimited 0.0.10 behavior.
- `/quds/ready` pings the database (and Redis when those drivers are enabled). `/quds/health` is unchanged.
- Database queue: reserve-then-ack (no delete-before-handle), stale reservation reclaim, `quds_failed_jobs` on final failure.
- SQL migrations take a portable lock so two processes cannot migrate at once.
- `Database.transaction()` facade over the bound connection.

## 0.0.10

### Phase A (additive; defaults unchanged)

- Opt-in `SecurityHeadersMiddleware` and `RequestIdMiddleware` (not applied globally).
- `Auth.issueTokens` for access/refresh token pairs.
- Async `Unique` / `Exists` validation rules.
- Opt-in Admin Insights routes behind `QUDS_INSIGHTS=true` and `QUDS_INSIGHTS_TOKEN` (Bearer), with replaceable `insightsAuthorizer` for future admin-role checks.

### Phase B (opt-in drivers)

- `RedisCacheDriver` + optional `CacheServiceProvider`; bind when `CACHE_DRIVER=redis`.
- `DatabaseQueueDriver`, `SerializableJob`, `JobRegistry`, and `Queue.cancel` (memory returns false / removes by id).
- Interval `Schedule.every` + export-only `ScheduleServiceProvider`.
- Optional `RedisBroadcastBridge` when `BROADCAST_DRIVER=redis`.
- Env auto-config in `registerProviders` / `serve` via `_configureDriversFromEnv` (no change unless env vars are set).

### Phase C (storage + migrations)

- Storage disks: `LocalStorageDisk` (default) and minimal S3-compatible `S3StorageDisk` (SigV4 PUT/HEAD/DELETE; `url()` from `S3_PUBLIC_URL`).
- SQL file migrations: `FileMigrationRunner` (`database/migrations/<id>/up.sql`), CLI `make:migration` / `migrate` / `migrate:rollback`, optional `MIGRATE_ON_BOOT`.
- Scaffold `.env` comments for optional drivers + `docker-compose.yml` (postgres + redis) on `qserver create`.

## 0.0.9

- Add `Cache` facade with in-memory driver and optional TTL (`Cache.put/get/forget/flush`).
- Strengthen queues: `Queue.later` / `Queue.at`, attempt tracking, and exponential backoff retries in the worker.
- Add opt-in `RateLimitMiddleware` (not applied globally).
- Register reserved health routes: `GET /quds/health` and `GET /quds/ready`.
- Layered env loading: `.env` then `.env.$APP_ENV` (falls back to `.env` / process env when files are missing).
- Add structured `Log` facade (`debug/info/warning/error`) plus `Log.recordQuery` slow-query hook; wire `LoggerMiddleware` to it.
- Harden WebSockets: configurable ping / idle timeout and `Auth.invalidate` closing related sockets.
- Expand validators: `IsInt`, `IsBool`, `IsUrl`, `IsConfirmed`, `InRule` (+ fluent helpers).
- CLI: `make:middleware`, `make:provider`, `cache:clear` help text, and `executables.qserver`.
- Add `QudsTestClient` / `QudsRouter.dispatchTest` for HTTP tests without binding a port.

## 0.0.8

- Enrich the terminal monitor: each request now shows time of day, path with query, duration, and client IP.
- Add `ExceptionHandlerMiddleware` to catch pipeline errors, map them to HTTP responses, and persist them for later review (`storage/logs/exceptions.log` plus an in-memory list / monitor panel).
- Allow a custom exception `handler` callback; unexpected errors are recorded even without the middleware via `GlobalExceptionHandler`.

## 0.0.7

- Update dependencies to latest compatible versions (`dart_jsonwebtoken` 3.x, `mime` 2.x, `lints` 6.x, and Quds DB packages).

## 0.0.6

- Disable the welcome dashboard by default; enable it explicitly with `showWelcomePage = true`.
- Hide sensitive console diagnostics (env, database, host, metrics, endpoints) unless `APP_ENV` is local/dev.
- Register `/quds/stats` only when the welcome page is enabled, and return 404 outside local environments.

## 0.0.5

- Serialize `DateTime` values in JSON responses as UTC (ISO 8601) for consistent, timezone-safe output.
- Harden broadcasting: reject client-initiated `publish` messages over WebSockets; events can only be emitted from the server.
- Remove the unused `sqflite_common_ffi` dependency and clean up unused imports.
- Resolve all static analysis issues in the library.

## 0.0.4

- Update quds_db dependencies; remove unused native assets and test files.

## 0.0.3

- Improve task controller and broadcasting features.

## 0.0.2

- Add `*.exe` to gitignore.

## 0.0.1

- Initial version.
