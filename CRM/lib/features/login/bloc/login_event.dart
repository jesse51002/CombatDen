import 'package:equatable/equatable.dart';

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
