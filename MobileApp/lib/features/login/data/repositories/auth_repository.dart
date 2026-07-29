import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository for authentication operations. Ported from the CRM's
/// `AuthRepository` — Supabase is the ONE token source; client roles hold no
/// DB privileges.
class AuthRepository {
  final SupabaseClient _supabase;

  AuthRepository({SupabaseClient? supabaseClient})
      : _supabase = supabaseClient ?? Supabase.instance.client;

  /// Sign in with email and password.
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

  /// Sign up with email and password.
  ///
  /// Returns the full [AuthResponse] so the caller can branch on
  /// `response.session`: when Supabase email confirmation is enabled the
  /// session is **null** (the user must click the emailed link before a
  /// session exists); when confirmation is off (or the address is
  /// auto-confirmed) the session is populated and the user is immediately
  /// authenticated. `response.user` is always populated on success.
  Future<AuthResponse> signUp({
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
      return response;
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('An unexpected error occurred');
    }
  }

  /// Re-send the sign-up confirmation email to [email]. Used from the
  /// "check your email" screen when the first link didn't arrive. Supabase
  /// silently ignores a resend for an already-confirmed address.
  Future<void> resendConfirmation(String email) async {
    try {
      await _supabase.auth.resend(
        type: OtpType.signup,
        email: email.trim(),
      );
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('Could not resend the confirmation email');
    }
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('Sign out failed');
    }
  }

  /// Get the current authenticated user.
  User? getCurrentUser() {
    return _supabase.auth.currentUser;
  }

  /// Stream of auth state changes.
  Stream<AuthState> get authStateChanges {
    return _supabase.auth.onAuthStateChange;
  }
}
