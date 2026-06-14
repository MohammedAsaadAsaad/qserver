import '../container/quds_env.dart';

class DashboardCard {
  final String title;
  final String content;
  final String? iconSvg;
  DashboardCard({required this.title, required this.content, this.iconSvg});
}

class DashboardEndpoint {
  final String method;
  final String path;
  final String description;
  DashboardEndpoint(
      {required this.method, required this.path, required this.description});
}

class ProjectInfoDashboard {
  static String render({
    String? welcomeHeading,
    String? welcomeSubheading,
    List<DashboardCard>? customCards,
    List<DashboardEndpoint>? endpoints,
    String? customHtml,
  }) {
    final appName = env<String>('APP_NAME', 'Quds Server Project')!;
    final appEnv = env<String>('APP_ENV', 'local')!;
    final appHost = env<String>('APP_HOST', '0.0.0.0')!;
    final appPort = env<int>('APP_PORT', 8000)!;
    final dbConnection = env<String>('DB_CONNECTION', 'postgres')!;
    final dbDatabase = env<String>('DB_DATABASE', 'quds_example_db')!;

    final finalWelcomeHeading = welcomeHeading ?? "Welcome to $appName";
    final finalWelcomeSubheading = welcomeSubheading ??
        "A comprehensive, expressive, and type-safe Dart backend framework.";

    // Render custom cards
    final cardsBuffer = StringBuffer();
    if (customCards != null) {
      for (var card in customCards) {
        final icon = card.iconSvg ??
            """
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904L9 21m0 0l-.813-5.096m.813 5.096l4-4M15 3h6m0 0v6m0-6L14 10" />
          </svg>
        """;
        cardsBuffer.write("""
        <section class="card">
          <h2 class="card-title">
            $icon
            ${card.title}
          </h2>
          <div style="font-size: 0.9rem; color: var(--text-muted); line-height: 1.6;">
            ${card.content}
          </div>
        </section>
        """);
      }
    }

    // Render endpoints
    final endpointsBuffer = StringBuffer();
    final endpointsList = endpoints ??
        [
          DashboardEndpoint(
              method: 'GET', path: '/', description: 'Dashboard UI'),
          DashboardEndpoint(
              method: 'WS', path: '/ws', description: 'WebSockets'),
        ];

    for (var ep in endpointsList) {
      final methodClass = 'method-${ep.method.toLowerCase()}';
      endpointsBuffer.write("""
      <div class="endpoint-item">
        <div class="endpoint-meta">
          <span class="method-badge $methodClass">${ep.method}</span>
          <span class="endpoint-path">${ep.path}</span>
        </div>
        <span class="endpoint-desc">${ep.description}</span>
      </div>
      """);
    }

    return """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$appName - Quds Server Console</title>
  
  <!-- Premium Typography -->
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&family=Space+Grotesk:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">
  
  <style>
    :root {
      --bg-dark: #07090e;
      --bg-card: rgba(13, 17, 28, 0.7);
      --bg-card-hover: rgba(20, 26, 42, 0.85);
      --border-color: rgba(255, 255, 255, 0.07);
      --border-color-hover: rgba(99, 102, 241, 0.25);
      
      --color-primary: #6366f1; /* Indigo */
      --color-primary-glow: rgba(99, 102, 241, 0.15);
      --color-secondary: #06b6d4; /* Cyan */
      --color-secondary-glow: rgba(6, 182, 212, 0.15);
      --color-success: #10b981; /* Emerald */
      --color-success-glow: rgba(16, 185, 129, 0.15);
      --color-warning: #f59e0b; /* Amber */
      
      --text-main: #f3f4f6;
      --text-muted: #9ca3af;
      --text-dark: #6b7280;
    }
    
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
      font-family: 'Plus Jakarta Sans', sans-serif;
      -webkit-font-smoothing: antialiased;
    }
    
    body {
      background-color: var(--bg-dark);
      color: var(--text-main);
      min-height: 100vh;
      overflow-x: hidden;
      background-image: 
        radial-gradient(circle at 10% 20%, rgba(99, 102, 241, 0.08) 0%, transparent 40%),
        radial-gradient(circle at 90% 80%, rgba(6, 182, 212, 0.08) 0%, transparent 40%),
        radial-gradient(circle at 50% 50%, rgba(13, 17, 28, 0.4) 0%, var(--bg-dark) 100%);
      background-attachment: fixed;
    }
    
    .container {
      max-width: 1280px;
      margin: 0 auto;
      padding: 2.5rem 1.5rem;
    }
    
    /* Header Styles */
    header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 3rem;
      position: relative;
    }
    
    header::after {
      content: '';
      position: absolute;
      bottom: -1rem;
      left: 0;
      right: 0;
      height: 1px;
      background: linear-gradient(90deg, rgba(255, 255, 255, 0.08) 0%, rgba(255, 255, 255, 0.02) 100%);
    }
    
    .brand {
      display: flex;
      align-items: center;
      gap: 0.75rem;
    }
    
    .logo-mark {
      width: 2.5rem;
      height: 2.5rem;
      background: linear-gradient(135deg, var(--color-primary) 0%, var(--color-secondary) 100%);
      border-radius: 0.75rem;
      display: flex;
      align-items: center;
      justify-content: center;
      font-family: 'Space Grotesk', sans-serif;
      font-weight: 700;
      font-size: 1.35rem;
      color: white;
      box-shadow: 0 0 20px var(--color-primary-glow);
    }
    
    .brand h1 {
      font-family: 'Space Grotesk', sans-serif;
      font-size: 1.5rem;
      font-weight: 700;
      letter-spacing: -0.02em;
      background: linear-gradient(to right, #ffffff, #9ca3af);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    
    .brand span {
      font-size: 0.75rem;
      padding: 0.15rem 0.5rem;
      background: rgba(255, 255, 255, 0.05);
      border: 1px solid var(--border-color);
      border-radius: 2rem;
      color: var(--text-muted);
      font-weight: 600;
      letter-spacing: 0.05em;
    }
    
    .system-status {
      display: flex;
      align-items: center;
      gap: 1.5rem;
    }
    
    .badge {
      display: inline-flex;
      align-items: center;
      gap: 0.5rem;
      padding: 0.4rem 0.85rem;
      border-radius: 2rem;
      font-size: 0.75rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.05em;
    }
    
    .badge-success {
      background: var(--color-success-glow);
      border: 1px solid rgba(16, 185, 129, 0.25);
      color: var(--color-success);
    }
    
    .pulse-dot {
      width: 6px;
      height: 6px;
      background-color: var(--color-success);
      border-radius: 50%;
      box-shadow: 0 0 10px var(--color-success);
      animation: pulse 2s infinite;
    }
    
    @keyframes pulse {
      0% {
        transform: scale(0.95);
        box-shadow: 0 0 0 0 rgba(16, 185, 129, 0.7);
      }
      70% {
        transform: scale(1);
        box-shadow: 0 0 0 6px rgba(16, 185, 129, 0);
      }
      100% {
        transform: scale(0.95);
        box-shadow: 0 0 0 0 rgba(16, 185, 129, 0);
      }
    }
    
    /* Grid Layout */
    .dashboard-grid {
      display: grid;
      grid-template-columns: 2fr 1fr;
      gap: 1.75rem;
    }
    
    @media (max-width: 968px) {
      .dashboard-grid {
        grid-template-columns: 1fr;
      }
    }
    
    /* Cards Layout */
    .card {
      background-color: var(--bg-card);
      border: 1px solid var(--border-color);
      border-radius: 1rem;
      padding: 1.75rem;
      backdrop-filter: blur(20px);
      transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
      position: relative;
      overflow: hidden;
    }
    
    .card:hover {
      background-color: var(--bg-card-hover);
      border-color: var(--border-color-hover);
      transform: translateY(-2px);
    }
    
    .card-title {
      font-family: 'Space Grotesk', sans-serif;
      font-size: 1.15rem;
      font-weight: 600;
      margin-bottom: 1.25rem;
      display: flex;
      align-items: center;
      gap: 0.6rem;
      letter-spacing: -0.01em;
    }
    
    .card-title svg {
      width: 1.25rem;
      height: 1.25rem;
      color: var(--color-primary);
    }
    
    /* Config Panel */
    .config-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 1.25rem;
    }
    
    .config-item {
      padding: 1rem;
      background: rgba(255, 255, 255, 0.015);
      border: 1px solid var(--border-color);
      border-radius: 0.75rem;
    }
    
    .config-label {
      font-size: 0.7rem;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: var(--text-dark);
      margin-bottom: 0.35rem;
      font-weight: 700;
    }
    
    .config-value {
      font-size: 0.95rem;
      font-weight: 600;
      color: var(--text-main);
    }
    
    .config-value.mono {
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.85rem;
    }
    
    /* Endpoints list */
    .endpoint-item {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 0.85rem;
      background: rgba(255, 255, 255, 0.01);
      border: 1px solid var(--border-color);
      border-radius: 0.5rem;
      margin-bottom: 0.75rem;
      transition: all 0.2s;
    }
    
    .endpoint-item:hover {
      background: rgba(255, 255, 255, 0.02);
      border-color: rgba(255, 255, 255, 0.12);
    }
    
    .endpoint-meta {
      display: flex;
      align-items: center;
      gap: 0.75rem;
    }
    
    .method-badge {
      font-size: 0.65rem;
      font-weight: 800;
      padding: 0.25rem 0.5rem;
      border-radius: 0.25rem;
      font-family: 'JetBrains Mono', monospace;
    }
    
    .method-get {
      background: rgba(16, 185, 129, 0.1);
      border: 1px solid rgba(16, 185, 129, 0.2);
      color: #34d399;
    }
    
    .method-post {
      background: rgba(6, 182, 212, 0.1);
      border: 1px solid rgba(6, 182, 212, 0.2);
      color: #22d3ee;
    }
    
    .method-ws {
      background: rgba(139, 92, 246, 0.1);
      border: 1px solid rgba(139, 92, 246, 0.2);
      color: #a78bfa;
    }
    
    .endpoint-path {
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.85rem;
      font-weight: 500;
    }
    
    .endpoint-desc {
      font-size: 0.75rem;
      color: var(--text-muted);
    }
    
    /* Live Stats Monitor */
    .metric-row {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 1rem;
      margin-bottom: 1.25rem;
    }
    
    .metric-card {
      background: rgba(0, 0, 0, 0.15);
      border: 1px solid var(--border-color);
      border-radius: 0.75rem;
      padding: 1rem;
      text-align: center;
    }
    
    .metric-value {
      font-family: 'Space Grotesk', sans-serif;
      font-size: 1.35rem;
      font-weight: 700;
      color: var(--color-secondary);
      margin-top: 0.25rem;
    }
    
    .metric-title {
      font-size: 0.7rem;
      color: var(--text-dark);
      text-transform: uppercase;
      letter-spacing: 0.05em;
      font-weight: 600;
    }
  </style>
</head>
<body>

  <div class="container">
    <header>
      <div class="brand">
        <div class="logo-mark">Q</div>
        <div>
          <div style="display: flex; align-items: center; gap: 0.5rem;">
            <h1>$appName</h1>
            <span>v0.0.1</span>
          </div>
          <p style="font-size: 0.75rem; color: var(--text-muted); margin-top: 0.15rem;">Quds Dart Server Framework Console</p>
        </div>
      </div>
      <div class="system-status">
        <div class="badge badge-success">
          <div class="pulse-dot"></div>
          Online
        </div>
      </div>
    </header>
    
    <div class="dashboard-grid">
      <!-- Main Column -->
      <div style="display: flex; flex-direction: column; gap: 1.75rem;">
        
        <!-- Welcome Hero Section -->
        <section class="card welcome-hero-card" style="background: linear-gradient(135deg, rgba(99, 102, 241, 0.15) 0%, rgba(6, 182, 212, 0.15) 100%); border-color: rgba(99, 102, 241, 0.25);">
          <div style="display: flex; flex-direction: column; gap: 0.75rem;">
            <h2 style="font-family: 'Space Grotesk', sans-serif; font-size: 1.75rem; font-weight: 800; background: linear-gradient(to right, #ffffff, #818cf8); -webkit-background-clip: text; -webkit-text-fill-color: transparent;">$finalWelcomeHeading</h2>
            <p style="font-size: 0.95rem; color: var(--text-muted); line-height: 1.55;">$finalWelcomeSubheading</p>
          </div>
        </section>
        
        <!-- Custom Cards Hook -->
        $cardsBuffer
        
        <!-- Config Overview -->
        <section class="card">
          <h2 class="card-title">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.43l-1.003.828c-.293.241-.438.613-.43.992a7.723 7.723 0 010 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.43l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.991l-1.004-.827a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.645-.869l.214-1.28z" />
              <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
            System Parameters
          </h2>
          <div class="config-grid">
            <div class="config-item">
              <div class="config-label">Environment</div>
              <div class="config-value">$appEnv</div>
            </div>
            <div class="config-item">
              <div class="config-label">Host Binding</div>
              <div class="config-value mono">$appHost:$appPort</div>
            </div>
            <div class="config-item">
              <div class="config-label">Database Connection</div>
              <div class="config-value">$dbConnection</div>
            </div>
            <div class="config-item">
              <div class="config-label">Database Name</div>
              <div class="config-value mono">$dbDatabase</div>
            </div>
          </div>
        </section>
        
        <!-- Custom HTML Injection Hook -->
        ${customHtml ?? ''}
      </div>
      
      <!-- Sidebar Column -->
      <div style="display: flex; flex-direction: column; gap: 1.75rem;">
        
        <!-- Live metrics -->
        <section class="card">
          <h2 class="card-title">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 13.5l10.5-11.25L12 10.5h8.25L9.75 21.75 12 13.5H3.75z" />
            </svg>
            Resource Monitor
          </h2>
          <div class="metric-row">
            <div class="metric-card">
              <div class="metric-title">Memory</div>
              <div class="metric-value" id="memValue">-</div>
            </div>
            <div class="metric-card">
              <div class="metric-title">Uptime</div>
              <div class="metric-value" id="uptimeValue">-</div>
            </div>
          </div>
          <div class="metric-row">
            <div class="metric-card">
              <div class="metric-title">WS Sockets</div>
              <div class="metric-value" id="wsValue">-</div>
            </div>
            <div class="metric-card">
              <div class="metric-title">Process ID</div>
              <div class="metric-value" id="pidValue">-</div>
            </div>
          </div>
        </section>
        
        <!-- API Route Directory -->
        <section class="card">
          <h2 class="card-title">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M13.19 8.688a4.5 4.5 0 011.242 7.244l-4.5 4.5a4.5 4.5 0 01-6.364-6.364l1.757-1.757m13.35-.622l1.757-1.757a4.5 4.5 0 00-6.364-6.364l-4.5 4.5a4.5 4.5 0 001.242 7.244" />
            </svg>
            API Endpoints
          </h2>
          <div>
            $endpointsBuffer
          </div>
        </section>
        
      </div>
    </div>
  </div>
  
  <script>
    async function updateStats() {
      try {
        const response = await fetch('/quds/stats');
        const data = await response.json();
        
        document.getElementById('memValue').textContent = data.memory;
        document.getElementById('uptimeValue').textContent = data.uptime;
        document.getElementById('wsValue').textContent = data.wsConnections;
        document.getElementById('pidValue').textContent = data.pid;
      } catch (err) {
        console.error('Failed to fetch system stats:', err);
      }
    }
    
    setInterval(updateStats, 2000);
    updateStats();
  </script>
</body>
</html>
""";
  }
}
