import 'package:equatable/equatable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Base class for login states
sealed class LoginState extends Equatable {
  const LoginState();

  @override
  List<Object?> get props => [];
}

/// Initial state before authentication check
class LoginInitial extends LoginState {
  const LoginInitial();
}

/// Loading state during authentication operations
class LoginLoading extends LoginState {
  const LoginLoading();
}

/// User is authenticated
class LoginAuthenticated extends LoginState {
  final User user;

  const LoginAuthenticated(this.user);

  @override
  List<Object?> get props => [user.id];
}

/// User is not authenticated
class LoginUnauthenticated extends LoginState {
  const LoginUnauthenticated();
}

/// Authentication error state
class LoginError extends LoginState {
  final String message;
  final bool isLoginError;

  const LoginError({
    required this.message,
    this.isLoginError = true,
  });

  @override
  List<Object?> get props => [message, isLoginError];
}

/// Registration success state (before navigation)
class LoginRegistrationSuccess extends LoginState {
  const LoginRegistrationSuccess();
}
