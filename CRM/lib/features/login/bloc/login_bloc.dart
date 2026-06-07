import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:crm/features/login/bloc/login_event.dart';
import 'package:crm/features/login/bloc/login_state.dart';
import 'package:crm/features/login/data/repositories/auth_repository.dart';

/// BLoC for managing authentication state
class LoginBloc extends Bloc<LoginEvent, LoginState> {
  /// Dev-only auto-login (gated by `--dart-define`). When both are
  /// set and no session exists on boot, the bloc signs in
  /// automatically so a fresh browser lands authenticated — used
  /// for QA / local dev. Empty in prod builds → normal login flow.
  static const String _devAutoLoginEmail =
      String.fromEnvironment('DEV_AUTOLOGIN_EMAIL');
  static const String _devAutoLoginPassword =
      String.fromEnvironment('DEV_AUTOLOGIN_PASSWORD');

  final AuthRepository _authRepository;
  late final StreamSubscription<AuthState>
      _authSubscription;

  LoginBloc({
    required AuthRepository authRepository,
  })  : _authRepository = authRepository,
        super(const LoginInitial()) {
    // Register event handlers
    on<LoginSignInRequested>(_onSignInRequested);
    on<LoginSignUpRequested>(_onSignUpRequested);
    on<LoginSignOutRequested>(_onSignOutRequested);
    on<LoginStatusChecked>(_onStatusChecked);

    // Listen to Supabase auth state changes so
    // that session expiry or external sign-outs
    // automatically redirect to login.
    _authSubscription =
        _authRepository.authStateChanges.listen(
      (authState) {
        if (authState.event ==
            AuthChangeEvent.signedOut) {
          add(const LoginSignOutRequested());
        }
      },
    );

    // Check initial auth status
    add(const LoginStatusChecked());
  }

  /// Handle sign in request
  Future<void> _onSignInRequested(
    LoginSignInRequested event,
    Emitter<LoginState> emit,
  ) async {
    emit(const LoginLoading());

    try {
      final user = await _authRepository.signInWithPassword(
        email: event.email,
        password: event.password,
      );
      emit(LoginAuthenticated(user));
    } on AuthException catch (e, stackTrace) {
      log('Sign in failed', error: e, stackTrace: stackTrace);

      final message = e.message.toLowerCase().contains('invalid')
          ? 'Invalid email or password'
          : 'An error occurred. Please try again.';

      emit(LoginError(message: message, isLoginError: true));
    } catch (e, stackTrace) {
      log('Sign in failed', error: e, stackTrace: stackTrace);
      emit(const LoginError(
        message: 'An unexpected error occurred',
        isLoginError: true,
      ));
    }
  }

  /// Handle sign up request
  Future<void> _onSignUpRequested(
    LoginSignUpRequested event,
    Emitter<LoginState> emit,
  ) async {
    emit(const LoginLoading());

    try {
      final user = await _authRepository.signUp(
        email: event.email,
        password: event.password,
      );
      // Automatically log in user after successful registration
      emit(LoginAuthenticated(user));
    } on AuthException catch (e, stackTrace) {
      log('Sign up failed', error: e, stackTrace: stackTrace);

      final message = e.message.toLowerCase().contains('already')
          ? 'This email is already registered'
          : 'An error occurred. Please try again.';

      emit(LoginError(message: message, isLoginError: false));
    } catch (e, stackTrace) {
      log('Sign up failed', error: e, stackTrace: stackTrace);
      emit(const LoginError(
        message: 'An unexpected error occurred',
        isLoginError: false,
      ));
    }
  }

  /// Handle sign out request
  Future<void> _onSignOutRequested(
    LoginSignOutRequested event,
    Emitter<LoginState> emit,
  ) async {
    // The auth-state listener re-dispatches this event whenever the session
    // turns null — and signOut() itself fires a `signedOut` event
    // unconditionally (even with no session). So calling signOut() again
    // when already signed out would re-fire the listener and loop forever,
    // freezing the app. Only hit signOut() when a session actually exists;
    // otherwise just reflect the already-signed-out state (this is the
    // re-entrant call from the listener, and the external/expiry case).
    if (_authRepository.getCurrentUser() == null) {
      emit(const LoginUnauthenticated());
      return;
    }
    try {
      await _authRepository.signOut();
      emit(const LoginUnauthenticated());
    } on AuthException catch (e, stackTrace) {
      log('Sign out failed', error: e, stackTrace: stackTrace);
      emit(LoginError(message: e.message));
      emit(const LoginUnauthenticated());
    } catch (e, stackTrace) {
      log('Sign out failed', error: e, stackTrace: stackTrace);
      emit(const LoginError(message: 'Sign out failed'));
      emit(const LoginUnauthenticated());
    }
  }

  /// Check current authentication status
  Future<void> _onStatusChecked(
    LoginStatusChecked event,
    Emitter<LoginState> emit,
  ) async {
    final user = _authRepository.getCurrentUser();

    if (user != null) {
      emit(LoginAuthenticated(user));
      return;
    }

    // Dev auto-login: with no session and dev creds defined, sign in
    // automatically (the sign-in handler emits Loading→Authenticated).
    if (_devAutoLoginEmail.isNotEmpty &&
        _devAutoLoginPassword.isNotEmpty) {
      add(
        LoginSignInRequested(
          email: _devAutoLoginEmail,
          password: _devAutoLoginPassword,
        ),
      );
      return;
    }

    emit(const LoginUnauthenticated());
  }

  @override
  Future<void> close() {
    _authSubscription.cancel();
    return super.close();
  }
}
