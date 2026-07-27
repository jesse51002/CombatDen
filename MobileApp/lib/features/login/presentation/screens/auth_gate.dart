import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/features/login/bloc/login_bloc.dart';
import 'package:mobile_app/features/login/bloc/login_state.dart';
import 'package:mobile_app/features/login/presentation/screens/login_screen.dart';
import 'package:mobile_app/features/login/presentation/screens/member_gate.dart';
import 'package:mobile_app/shared/widgets/loading_screen.dart';

/// The app root. Decides the whole subtree from [LoginBloc] state:
///
/// - [LoginInitial] → a branded boot splash while the initial auth check runs.
/// - [LoginAuthenticated] → the [MemberGate], which resolves the member
///   identity, hydrates the gym theme, and mounts the app.
/// - anything else (unauthenticated / loading a submit / error / awaiting
///   confirmation) → the [_AuthFlow] (login ↔ register ↔ verify).
///
/// The unauthenticated states all fall to `_AuthFlow`, whose nested [Navigator]
/// element is preserved across those rebuilds — so a pushed register screen
/// (and the password it holds for the "I've confirmed, continue" re-sign-in)
/// survives the loading/error/awaiting transitions. The whole subtree is torn
/// down on sign-out, returning to the login screen cleanly.
class AuthGate extends StatelessWidget {
  /// The app route table from `main.dart`, reused by the authenticated app's
  /// nested navigator so it stays a single source of truth.
  final Route<dynamic> Function(RouteSettings) onGenerateRoute;

  const AuthGate({super.key, required this.onGenerateRoute});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoginBloc, LoginState>(
      builder: (context, state) {
        return switch (state) {
          // Only the initial boot auth-check shows a full-screen splash.
          // A LoginLoading from a submit keeps the auth flow mounted (so the
          // form shows its own inline state) — it falls to the default below.
          LoginInitial() => const LoadingScreen(),
          LoginAuthenticated() => MemberGate(onGenerateRoute: onGenerateRoute),
          _ => const _AuthFlow(),
        };
      },
    );
  }
}

/// The unauthenticated flow: a nested [Navigator] rooted at the [LoginScreen],
/// with the register screen pushed on top. Kept as its own widget so the
/// navigator's route stack (and the register form's retained password) survive
/// the login bloc's loading/error/awaiting rebuilds.
class _AuthFlow extends StatelessWidget {
  const _AuthFlow();

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        builder: (_) => const LoginScreen(),
      ),
    );
  }
}
