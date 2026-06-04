import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:crm/core/constants/env_constants.dart';

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
}
