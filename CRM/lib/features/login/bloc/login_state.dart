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

/// Sign-up succeeded but the account still needs email confirmation before a
/// session exists (Supabase `enable_confirmations` is on). Carries the [email]
/// the confirmation link was sent to, shown on the "check your email" screen.
/// [resent] flips true after a successful resend so the UI can acknowledge it.
/// The user leaves this state when the emailed link lands and the external
/// session listener flips the app to [LoginAuthenticated].
class LoginAwaitingEmailConfirmation extends LoginState {
  final String email;
  final bool resent;

  const LoginAwaitingEmailConfirmation(this.email, {this.resent = false});

  @override
  List<Object?> get props => [email, resent];
}
