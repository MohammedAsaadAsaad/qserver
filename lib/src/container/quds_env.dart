import 'dart:io';

class QudsEnv {
  static final Map<String, String> _vars = {};
  static bool _loaded = false;

  /// Loads variables from the system and layered `.env` files.
  ///
  /// Order (later wins):
  /// 1. [Platform.environment]
  /// 2. `.env` when present (or [path])
  /// 3. `.env.$APP_ENV` when present (`APP_ENV` defaults to `local`)
  static Future<void> load({String path = '.env'}) async {
    _vars
      ..clear()
      ..addAll(Platform.environment);

    final baseLoaded = await _loadFile(path);

    final appEnv = (_vars['APP_ENV'] ?? 'local').trim();
    final parent = File(path).parent.path;
    final layeredPath =
        parent == '.' ? '.env.$appEnv' : '$parent${Platform.pathSeparator}.env.$appEnv';

    var layeredLoaded = false;
    if (layeredPath != path) {
      layeredLoaded = await _loadFile(layeredPath);
    }

    if (!baseLoaded && !layeredLoaded) {
      print(
        'ℹ️  No .env file found. Relying on system environment variables.',
      );
    }

    _loaded = true;
  }

  static Future<bool> _loadFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return false;

    print('📂 Loading env file from: ${file.absolute.path}');
    final lines = await file.readAsLines();
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final separatorIndex = line.indexOf('=');
      if (separatorIndex == -1) continue;

      final key = line.substring(0, separatorIndex).trim();
      var value = line.substring(separatorIndex + 1).trim();

      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }

      _vars[key] = value;
    }
    return true;
  }

  /// Retrieves an environment variable and casts it to the requested type.
  static T? get<T>(String key, [T? defaultValue]) {
    if (!_vars.containsKey(key)) return defaultValue;

    final val = _vars[key]!;

    if (T == int) return int.tryParse(val) as T? ?? defaultValue;
    if (T == bool) {
      return (val.toLowerCase() == 'true' || val == '1') as T? ?? defaultValue;
    }
    if (T == double) return double.tryParse(val) as T? ?? defaultValue;

    return val as T;
  }

  /// Whether [load] has been called at least once in this process.
  static bool get isLoaded => _loaded;
}

/// Global helper mirroring Laravel's env() function
T? env<T>(String key, [T? defaultValue]) => QudsEnv.get<T>(key, defaultValue);

/// True when [APP_ENV] is a local/dev value (default: `local`).
bool isLocalEnvironment() {
  final value = (env<String>('APP_ENV', 'local') ?? 'local').toLowerCase();
  return value == 'local' || value == 'development' || value == 'dev';
}
