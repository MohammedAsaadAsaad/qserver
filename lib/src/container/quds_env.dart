import 'dart:io';

class QudsEnv {
  static final Map<String, String> _vars = {};

  /// Loads variables from the system and the .env file.
  static Future<void> load({String path = '.env'}) async {
    // 1. Load OS-level environment variables first (for Docker/Production)
    _vars.addAll(Platform.environment);

    // 2. Load and override with local .env file if it exists
    final file = File(path);
    print('📂 Loading .env file from: ${file.absolute.path}');
    if (await file.exists()) {
      final lines = await file.readAsLines();
      for (var line in lines) {
        line = line.trim();
        // Ignore empty lines and comments
        if (line.isEmpty || line.startsWith('#')) continue;

        final separatorIndex = line.indexOf('=');
        if (separatorIndex != -1) {
          final key = line.substring(0, separatorIndex).trim();
          var value = line.substring(separatorIndex + 1).trim();

          // Strip surrounding quotes if the developer wrote APP_KEY="secret"
          if ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'"))) {
            value = value.substring(1, value.length - 1);
          }

          _vars[key] = value;
        }
      }
    } else {
      print('ℹ️  No .env file found. Relying on system environment variables.');
    }
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

    return val as T; // Defaults to returning a String
  }
}

/// Global helper mirroring Laravel's env() function
T? env<T>(String key, [T? defaultValue]) => QudsEnv.get<T>(key, defaultValue);
