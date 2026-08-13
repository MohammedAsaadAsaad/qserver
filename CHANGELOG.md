## 0.0.1

- Initial version.

## 0.0.2

- Add *.exe to gitignore


## 0.0.3

- improve task controller and broadcasting features

## 0.0.4

- Update quds_db dependencies; remove unused native assets and test files

## 0.0.5

- Serialize `DateTime` values in JSON responses as UTC (ISO 8601) for consistent, timezone-safe output.
- Harden broadcasting: reject client-initiated `publish` messages over WebSockets; events can only be emitted from the server.
- Remove the unused `sqflite_common_ffi` dependency and clean up unused imports.
- Resolve all static analysis issues in the library.

## 0.0.6

- Disable the welcome dashboard by default; enable it explicitly with `showWelcomePage = true`.
- Hide sensitive console diagnostics (env, database, host, metrics, endpoints) unless `APP_ENV` is local/dev.
- Register `/quds/stats` only when the welcome page is enabled, and return 404 outside local environments.

## 0.0.7

- Update dependencies to latest compatible versions (`dart_jsonwebtoken` 3.x, `mime` 2.x, `lints` 6.x, and Quds DB packages).

## 0.0.8

- Enrich the terminal monitor: each request now shows time of day, path with query, duration, and client IP.
- Add `ExceptionHandlerMiddleware` to catch pipeline errors, map them to HTTP responses, and persist them for later review (`storage/logs/exceptions.log` plus an in-memory list / monitor panel).
- Allow a custom exception `handler` callback; unexpected errors are recorded even without the middleware via `GlobalExceptionHandler`.

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
