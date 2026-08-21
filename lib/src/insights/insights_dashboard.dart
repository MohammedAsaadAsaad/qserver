/// HTML UI for Admin Insights (`GET /quds/insights`).
class InsightsDashboard {
  static String loginPage() {
    return _shell(
      title: 'Insights — sign in',
      body: '''
      <section class="card">
        <h2>Admin Insights</h2>
        <p class="muted">Enter the Insights bearer token to open the dashboard.</p>
        <form id="token-form">
          <input id="token" type="password" placeholder="QUDS_INSIGHTS_TOKEN" autocomplete="off" />
          <button type="submit">Open dashboard</button>
        </form>
      </section>
      <script>
        document.getElementById('token-form').addEventListener('submit', function (e) {
          e.preventDefault();
          var token = document.getElementById('token').value.trim();
          if (!token) return;
          sessionStorage.setItem('quds_insights_token', token);
          location.search = '?token=' + encodeURIComponent(token);
        });
      </script>
      ''',
    );
  }

  static String page() {
    return _shell(
      title: 'Insights',
      body: '''
      <header>
        <div>
          <h1>Insights</h1>
          <p class="muted">Exceptions and readiness for this process</p>
        </div>
        <span id="ready-badge" class="badge">…</span>
      </header>
      <section class="grid">
        <div class="card">
          <h2>Health</h2>
          <pre id="health">Loading…</pre>
        </div>
        <div class="card">
          <h2>Summary</h2>
          <pre id="summary">Loading…</pre>
        </div>
      </section>
      <section class="card">
        <h2>Recent exceptions</h2>
        <div id="exceptions">Loading…</div>
      </section>
      <section class="card">
        <h2>Failed jobs</h2>
        <div id="failed-jobs">Loading…</div>
      </section>
      <script>
        function token() {
          var params = new URLSearchParams(location.search);
          var fromQuery = params.get('token');
          if (fromQuery) {
            sessionStorage.setItem('quds_insights_token', fromQuery);
            return fromQuery;
          }
          return sessionStorage.getItem('quds_insights_token') || '';
        }
        async function loadJson(path) {
          var headers = {};
          var t = token();
          if (t) headers['Authorization'] = 'Bearer ' + t;
          var res = await fetch(path, { headers: headers });
          if (res.status === 401) {
            location.href = '/quds/insights';
            return null;
          }
          return res.json();
        }
        function esc(s) {
          return String(s).replace(/[&<>]/g, function (c) {
            return ({'&':'&amp;','<':'&lt;','>':'&gt;'})[c];
          });
        }
        async function refresh() {
          var health = await loadJson('/quds/insights/health-summary');
          var ready = await fetch('/quds/ready').then(function (r) { return r.json(); }).catch(function () { return null; });
          var ex = await loadJson('/quds/insights/exceptions?limit=25&stack=0');
          var jobs = await loadJson('/quds/insights/failed-jobs?limit=25');
          if (health) {
            document.getElementById('summary').textContent = JSON.stringify(health, null, 2);
          }
          if (ready) {
            document.getElementById('health').textContent = JSON.stringify(ready, null, 2);
            var badge = document.getElementById('ready-badge');
            var ok = ready.status === 'ready';
            badge.textContent = ok ? 'Ready' : 'Not ready';
            badge.className = 'badge ' + (ok ? 'ok' : 'bad');
          }
          if (ex && Array.isArray(ex.data)) {
            if (ex.data.length === 0) {
              document.getElementById('exceptions').innerHTML = '<p class="muted">No exceptions captured.</p>';
            } else {
              document.getElementById('exceptions').innerHTML = ex.data.map(function (row) {
                return '<article class="ex"><div class="ex-meta">' +
                  esc(row.time || '') + ' · ' + esc(row.method || '') + ' ' + esc(row.path || '') +
                  '</div><div class="ex-msg">' + esc(row.errorType || '') + ': ' + esc(row.message || '') +
                  '</div></article>';
              }).join('');
            }
          }
          if (jobs && Array.isArray(jobs.data)) {
            if (jobs.data.length === 0) {
              document.getElementById('failed-jobs').innerHTML = '<p class="muted">No failed jobs.</p>';
            } else {
              document.getElementById('failed-jobs').innerHTML = jobs.data.map(function (row) {
                return '<article class="ex"><div class="ex-meta">' +
                  esc(row.time || '') + ' · ' + esc(row.label || row.jobType || '') +
                  ' · attempt ' + esc(String(row.attempts || '')) +
                  '</div><div class="ex-msg">' + esc(row.error || '') + '</div></article>';
              }).join('');
            }
          }
        }
        refresh();
        setInterval(refresh, 4000);
      </script>
      ''',
    );
  }

  static String _shell({required String title, required String body}) {
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>$title</title>
  <style>
    :root {
      --bg: #07090e;
      --card: rgba(13, 17, 28, 0.75);
      --border: rgba(255, 255, 255, 0.08);
      --text: #f3f4f6;
      --muted: #9ca3af;
      --ok: #10b981;
      --bad: #f43f5e;
      --accent: #6366f1;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: ui-sans-serif, system-ui, sans-serif;
      background: var(--bg);
      color: var(--text);
      min-height: 100vh;
    }
    .wrap { max-width: 960px; margin: 0 auto; padding: 2rem 1.25rem; }
    header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.5rem; }
    h1, h2 { margin: 0 0 0.5rem; }
    .muted { color: var(--muted); font-size: 0.9rem; }
    .card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 1rem;
      padding: 1.25rem;
      margin-bottom: 1rem;
    }
    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
    @media (max-width: 800px) { .grid { grid-template-columns: 1fr; } }
    pre {
      white-space: pre-wrap;
      word-break: break-word;
      font-size: 0.8rem;
      color: #cbd5e1;
    }
    input {
      width: 100%;
      padding: 0.7rem 0.85rem;
      border-radius: 0.6rem;
      border: 1px solid var(--border);
      background: #0b1020;
      color: var(--text);
      margin: 0.75rem 0;
    }
    button {
      background: var(--accent);
      color: white;
      border: 0;
      border-radius: 0.6rem;
      padding: 0.65rem 1rem;
      font-weight: 600;
      cursor: pointer;
    }
    .badge {
      padding: 0.35rem 0.75rem;
      border-radius: 2rem;
      font-size: 0.75rem;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.04em;
      border: 1px solid var(--border);
    }
    .badge.ok { color: var(--ok); border-color: rgba(16, 185, 129, 0.35); }
    .badge.bad { color: var(--bad); border-color: rgba(244, 63, 94, 0.35); }
    .ex { padding: 0.75rem 0; border-bottom: 1px solid var(--border); }
    .ex-meta { font-size: 0.75rem; color: var(--muted); margin-bottom: 0.25rem; }
    .ex-msg { font-size: 0.9rem; }
  </style>
</head>
<body>
  <div class="wrap">
    $body
  </div>
</body>
</html>
''';
  }
}
