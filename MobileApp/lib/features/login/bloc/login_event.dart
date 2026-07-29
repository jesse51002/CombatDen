import 'package:equatable/equatable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Base class for login events.
sealed class LoginEvent extends Equatable {
  const LoginEvent();

  @override
  List<Object?> get props => [];
}

/// Sign in with email and password.
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

/// Sign up with email and password.
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

/// Sign out.
class LoginSignOutRequested extends LoginEvent {
  const LoginSignOutRequested();
}

/// Check authentication status (fired once by the bloc constructor).
class LoginStatusChecked extends LoginEvent {
  const LoginStatusChecked();
}

/// Re-send the sign-up confirmation email (from the "check your email" screen).
class LoginResendConfirmationRequested extends LoginEvent {
  final String email;

  const LoginResendConfirmationRequested(this.email);

  @override
  List<Object?> get props => [email];
}

/// Internal event: a Supabase session arrived from outside the login form — a
/// persisted session on boot, the email-confirmation link landing, or a token
/// refresh. Carries the [user] so the bloc can mark the app authenticated
/// without re-reading the client.
class LoginExternalSessionDetected extends LoginEvent {
  final User user;

  const LoginExternalSessionDetected(this.user);

  @override
  List<Object?> get props => [user.id];
}
