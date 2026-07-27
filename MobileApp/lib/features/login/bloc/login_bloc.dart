import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile_app/features/login/bloc/login_event.dart';
import 'package:mobile_app/features/login/bloc/login_state.dart';
import 'package:mobile_app/features/login/data/repositories/auth_repository.dart';

/// BLoC for managing authentication state. Ported from the CRM `LoginBloc`.
class LoginBloc extends Bloc<LoginEvent, LoginState> {
  /// Dev-only auto-login (gated by `--dart-define`). When both are set and no
  /// session exists on boot, the bloc signs in automatically so a fresh app
  /// lands authenticated — used for QA / local dev. Empty in prod builds →
  /// normal login flow.
  static const String _devAutoLoginEmail =
      String.fromEnvironment('DEV_AUTOLOGIN_EMAIL');
  static const String _devAutoLoginPassword =
      String.fromEnvironment('DEV_AUTOLOGIN_PASSWORD');

  final AuthRepository _authRepository;
  late final StreamSubscription<AuthState> _authSubscription;

  LoginBloc({required AuthRepository authRepository})
      : _authRepository = authRepository,
        super(const LoginInitial()) {
    on<LoginSignInRequested>(_onSignInRequested);
    on<LoginSignUpRequested>(_onSignUpRequested);
    on<LoginSignOutRequested>(_onSignOutRequested);
    on<LoginStatusChecked>(_onStatusChecked);
    on<LoginResendConfirmationRequested>(_onResendConfirmationRequested);
    on<LoginExternalSessionDetected>(_onExternalSessionDetected);

    // Listen to Supabase auth state changes. A session turning null (expiry /
    // external sign-out) redirects to login; a session ARRIVING from outside
    // the login form — a persisted session on boot, the email-confirmation
    // link landing (Supabase fires `signedIn`), or a token refresh
    // (`userUpdated`) — flips the app to authenticated. This catches the
    // confirmation-link landing and closes the race where `LoginStatusChecked`
    // ran before the session landed and stranded the app on the login screen.
    _authSubscription = _authRepository.authStateChanges.listen((authState) {
      final event = authState.event;
      if (event == AuthChangeEvent.signedOut) {
        add(const LoginSignOutRequested());
      } else if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.initialSession ||
          event == AuthChangeEvent.userUpdated) {
        final session = authState.session;
        if (session != null) {
          add(LoginExternalSessionDetected(session.user));
        }
      }
    });

    add(const LoginStatusChecked());
  }

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

  Future<void> _onSignUpRequested(
    LoginSignUpRequested event,
    Emitter<LoginState> emit,
  ) async {
    emit(const LoginLoading());
    try {
      final response = await _authRepository.signUp(
        email: event.email,
        password: event.password,
      );
      if (response.session != null) {
        // Confirmations off / auto-confirmed: a session came back, so the user
        // is already authenticated. (The external listener also sees this
        // `signedIn`, but the emit here is deduped.)
        emit(LoginAuthenticated(response.user!));
      } else {
        // Confirmations on: no session yet. Hold on the "check your email"
        // screen until the emailed link lands and the external-session
        // listener flips the app to authenticated.
        emit(LoginAwaitingEmailConfirmation(event.email));
      }
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

  /// Handle a confirmation-email resend from the "check your email" screen.
  /// Keeps the user on [LoginAwaitingEmailConfirmation]; on success flips
  /// `resent` so the UI can acknowledge it.
  Future<void> _onResendConfirmationRequested(
    LoginResendConfirmationRequested event,
    Emitter<LoginState> emit,
  ) async {
    try {
      await _authRepository.resendConfirmation(event.email);
      emit(LoginAwaitingEmailConfirmation(event.email, resent: true));
    } catch (e, stackTrace) {
      log('Resend confirmation failed', error: e, stackTrace: stackTrace);
      // Stay on the confirmation screen; the user can try again.
      emit(LoginAwaitingEmailConfirmation(event.email));
    }
  }

  /// Handle a session that arrived from outside the login form. Mark the app
  /// authenticated, guarding against a redundant emit for the same user.
  Future<void> _onExternalSessionDetected(
    LoginExternalSessionDetected event,
    Emitter<LoginState> emit,
  ) async {
    final current = state;
    if (current is LoginAuthenticated && current.user.id == event.user.id) {
      return;
    }
    emit(LoginAuthenticated(event.user));
  }

  /// Handle sign out. The auth-state listener re-dispatches this event whenever
  /// the session turns null — and signOut() itself fires a `signedOut` event
  /// unconditionally (even with no session). So calling signOut() again when
  /// already signed out would re-fire the listener and loop forever, freezing
  /// the app. Only hit signOut() when a session actually exists; otherwise just
  /// reflect the already-signed-out state (the re-entrant call from the
  /// listener, and the external/expiry case).
  Future<void> _onSignOutRequested(
    LoginSignOutRequested event,
    Emitter<LoginState> emit,
  ) async {
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

  /// Check current authentication status.
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
    if (_devAutoLoginEmail.isNotEmpty && _devAutoLoginPassword.isNotEmpty) {
      add(LoginSignInRequested(
        email: _devAutoLoginEmail,
        password: _devAutoLoginPassword,
      ));
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
