import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile_app/core/config/environment.dart';
import 'package:mobile_app/core/constants/env_constants.dart';

/// Supabase configuration and initialization
class SupabaseConfig {
  // Private constructor to prevent instantiation
  SupabaseConfig._();

  /// Initialize Supabase with environment-specific configuration
  static Future<void> initialize() async {
    // Load environment variables
    await EnvironmentConfig.load();

    // Get Supabase credentials from environment. The URL goes through
    // [EnvironmentConfig.url] so a loopback host is rewritten to `10.0.2.2`
    // on the Android emulator (see EnvironmentConfig.url).
    final supabaseUrl = EnvironmentConfig.url(EnvConstants.supabaseUrl);
    final supabaseAnonKey = EnvironmentConfig.get(EnvConstants.supabaseAnonKey);

    // Initialize Supabase. supabase_flutter 2.16 deprecated `anonKey` in favor
    // of `publishableKey`; our key is the new `sb_publishable_...` format, so
    // this is the correct (and warning-free) parameter. The env var keeps the
    // `SUPABASE_ANON_KEY` name for parity with the CRM's config shape.
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
  }

  /// Get the Supabase client instance
  static SupabaseClient get client => Supabase.instance.client;
}
