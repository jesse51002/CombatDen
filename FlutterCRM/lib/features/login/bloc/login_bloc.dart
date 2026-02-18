import 'dart:developer';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm/features/login/bloc/login_event.dart';
import 'package:crm/features/login/bloc/login_state.dart';
import 'package:crm/features/login/data/repositories/auth_repository.dart';

/// BLoC for managing authentication state
class LoginBloc extends Bloc<LoginEvent, LoginState> {
  final AuthRepository _authRepository;

  LoginBloc({
    required AuthRepository authRepository,
  })  : _authRepository = authRepository,
        super(const LoginInitial()) {
    // Register event handlers
    on<LoginSignInRequested>(_onSignInRequested);
    on<LoginSignUpRequested>(_onSignUpRequested);
    on<LoginSignOutRequested>(_onSignOutRequested);
    on<LoginStatusChecked>(_onStatusChecked);

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
      emit(const LoginUnauthenticated());
    } catch (e, stackTrace) {
      log('Sign in failed', error: e, stackTrace: stackTrace);
      emit(const LoginError(
        message: 'An unexpected error occurred',
        isLoginError: true,
      ));
      emit(const LoginUnauthenticated());
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
      emit(const LoginUnauthenticated());
    } catch (e, stackTrace) {
      log('Sign up failed', error: e, stackTrace: stackTrace);
      emit(const LoginError(
        message: 'An unexpected error occurred',
        isLoginError: false,
      ));
      emit(const LoginUnauthenticated());
    }
  }

  /// Handle sign out request
  Future<void> _onSignOutRequested(
    LoginSignOutRequested event,
    Emitter<LoginState> emit,
  ) async {
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
    } else {
      emit(const LoginUnauthenticated());
    }
  }
}
