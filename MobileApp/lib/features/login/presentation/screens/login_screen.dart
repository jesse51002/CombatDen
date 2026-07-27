import 'package:flutter/material.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/login/presentation/widgets/login_form.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// Unauthenticated entry point — full-screen, dark-native email + password
/// sign-in. Mounted by the unauthenticated flow inside [AuthGate]; the
/// [LoginBloc] is provided above the gate in `main.dart`.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScreenScaffold(
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            vertical: DesignConstants.paddingBig,
          ),
          child: LoginForm(),
        ),
      ),
    );
  }
}
