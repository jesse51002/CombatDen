import 'package:equatable/equatable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Base class for login events
sealed class LoginEvent extends Equatable {
  const LoginEvent();

  @override
  List<Object?> get props => [];
}

/// Event to sign in with email and password
class LoginSignInRequested extends LoginEvent {
  final String email;
  final String password;

  const LoginSignInRequested({
    required this.email,
    required this.password,
  });

  @override
  List<Object?> get props => [email, password];
}

/// Event to sign up with email and password
class LoginSignUpRequested extends LoginEvent {
  final String email;
  final String password;

  const LoginSignUpRequested({
    required this.email,
    required this.password,
  });

  @override
  List<Object?> get props => [email, password];
}

/// Event to sign out
class LoginSignOutRequested extends LoginEvent {
  const LoginSignOutRequested();
}

/// Event to check authentication status
class LoginStatusChecked extends LoginEvent {
  const LoginStatusChecked();
}

/// Event to re-send the sign-up confirmation email (from the
/// "check your email" screen).
class LoginResendConfirmationRequested extends LoginEvent {
  final String email;

  const LoginResendConfirmationRequested(this.email);

  @override
  List<Object?> get props => [email];
}

/// Internal event: a Supabase session arrived from outside the login form — a
/// persisted session on boot, the email-confirmation link landing on web, a
/// token refresh, or password recovery. Carries the [user] so the bloc can
/// mark the app authenticated without re-reading the client.
class LoginExternalSessionDetected extends LoginEvent {
  final User user;

  const LoginExternalSessionDetected(this.user);

  @override
  List<Object?> get props => [user.id];
}
