# Quds Task API example

A small backend that shows routing, JWT auth, background jobs (with a terminal
preloader), WebSockets, cache, health checks, and Insights.

## Run

```bash
cd example
dart pub get
dart run lib/main.dart
```

Postgres is optional. If `DB_*` is unreachable, tasks stay in memory and the
server still starts.

## Try

```bash
# Register and call a protected route
curl -s -X POST http://127.0.0.1:8000/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"ada@example.com","password":"secret123","name":"Ada"}'

curl -s http://127.0.0.1:8000/api/v1/me \
  -H "Authorization: Bearer <accessToken>"

# Queue jobs (watch ⠋ then ✓ in the terminal)
curl -s -X POST http://127.0.0.1:8000/api/v1/tasks \
  -H 'Content-Type: application/json' \
  -d '{"title":"Ship README","description":"Write the getting-started section"}'

curl -s -X POST http://127.0.0.1:8000/api/v1/demo/export \
  -H 'Content-Type: application/json' \
  -d '{"name":"weekly"}'

# Insights dashboard
open 'http://127.0.0.1:8000/quds/insights?token=demo-insights'
```

WebSocket channel: `ws://127.0.0.1:8000/ws` subscribe `public.tasks`.
