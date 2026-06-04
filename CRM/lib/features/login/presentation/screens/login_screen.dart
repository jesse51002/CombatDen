import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/login/presentation/widgets/login_form.dart';

/// Unauthenticated entry point — email + password sign-in.
///
/// Mounted by [AuthGate] for all unauthenticated / error
/// states. Provides the [LoginBloc] from the parent context
/// (wired in `main.dart`'s `_AuthGateHost`).
///
/// Layout: cool off-white [DesignConstants.backgroundColor]
/// fill, centred card that constrains to 480px max-width.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignConstants.backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DesignConstants.paddingBig),
          child: const LoginForm(),
        ),
      ),
    );
  }
}
