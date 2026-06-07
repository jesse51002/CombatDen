import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm/core/config/environment.dart';
import 'package:crm/core/constants/env_constants.dart';

/// Supabase configuration and initialization
class SupabaseConfig {
  // Private constructor to prevent instantiation
  SupabaseConfig._();

  /// Initialize Supabase with environment-specific configuration
  static Future<void> initialize() async {
    // Load environment variables
    await EnvironmentConfig.load();

    // Get Supabase credentials from environment
    final supabaseUrl = EnvironmentConfig.get(EnvConstants.supabaseUrl);
    final supabaseAnonKey = EnvironmentConfig.get(EnvConstants.supabaseAnonKey);

    // Initialize Supabase
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  /// Get the Supabase client instance
  static SupabaseClient get client => Supabase.instance.client;
}
