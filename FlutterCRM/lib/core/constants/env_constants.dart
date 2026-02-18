/// Environment constants for configuration management
class EnvConstants {
  // Private constructor to prevent instantiation
  EnvConstants._();

  // Environment file paths
  static const String devEnvFile = '.env.dev';
  static const String prodEnvFile = '.env.prod';

  // Environment variable keys
  static const String supabaseUrl = 'SUPABASE_URL';
  static const String supabaseAnonKey = 'SUPABASE_ANON_KEY';
}
