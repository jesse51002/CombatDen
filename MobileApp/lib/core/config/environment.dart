import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mobile_app/core/constants/env_constants.dart';

/// Environment types for the application
enum Environment {
  dev,
  prod,
}

/// Environment configuration manager
class EnvironmentConfig {
  // Private constructor to prevent instantiation
  EnvironmentConfig._();

  /// Get the current environment based on build mode
  /// Debug builds use dev, release builds use prod
  static Environment get currentEnvironment {
    if (kDebugMode) {
      return Environment.dev;
    }
    return Environment.prod;
  }

  /// Get the appropriate .env file path for the current environment
  static String get envFilePath {
    switch (currentEnvironment) {
      case Environment.dev:
        return EnvConstants.devEnvFile;
      case Environment.prod:
        return EnvConstants.prodEnvFile;
    }
  }

  /// Load the environment file for the current environment
  static Future<void> load() async {
    await dotenv.load(fileName: envFilePath);
  }

  /// Get environment variable value by key
  static String get(String key) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw Exception('Environment variable $key not found or empty');
    }
    return value;
  }

  /// Like [get], but rewrites a loopback host so the URL is reachable from an
  /// Android emulator. The emulator runs in its own VM and cannot see the host
  /// machine's `localhost` / `127.0.0.1`; Android maps the host loopback to the
  /// special alias `10.0.2.2`. Apply this to URL-valued keys (SUPABASE_URL,
  /// API_BASE_URL) so the same `.env.dev` works on emulator, device (via
  /// `adb reverse`), and iOS. No-op on web, iOS, desktop, and for any
  /// non-loopback host (a real domain like `api.combatden.net` is untouched).
  static String url(String key) => _rewriteHostForAndroid(get(key));

  static String _rewriteHostForAndroid(String value) {
    if (!kIsWeb && Platform.isAndroid) {
      return value
          .replaceFirst('localhost', '10.0.2.2')
          .replaceFirst('127.0.0.1', '10.0.2.2');
    }
    return value;
  }
}
