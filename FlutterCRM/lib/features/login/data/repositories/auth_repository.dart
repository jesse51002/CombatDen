import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository for authentication operations
class AuthRepository {
  final SupabaseClient _supabase;

  AuthRepository({SupabaseClient? supabaseClient})
      : _supabase = supabaseClient ?? Supabase.instance.client;

  /// Sign in with email and password
  Future<User> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      if (response.user == null) {
        throw AuthException('Sign in failed');
      }

      return response.user!;
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('An unexpected error occurred');
    }
  }

  /// Sign up with email and password
  Future<User> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email.trim(),
        password: password,
      );

      if (response.user == null) {
        throw AuthException('Sign up failed');
      }

      return response.user!;
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('An unexpected error occurred');
    }
  }

  /// Sign out the current user
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('Sign out failed');
    }
  }

  /// Get the current authenticated user
  User? getCurrentUser() {
    return _supabase.auth.currentUser;
  }

  /// Stream of auth state changes
  Stream<AuthState> get authStateChanges {
    return _supabase.auth.onAuthStateChange;
  }
}
