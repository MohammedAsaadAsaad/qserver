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