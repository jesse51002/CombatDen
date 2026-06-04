import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/login/presentation/widgets/register_form.dart';

/// Registration screen — email + password + confirm sign-up.
///
/// Navigated to from [LoginScreen] via [LoginForm]'s "Sign up"
/// link. Shares the same [LoginBloc] from the tree (wired in
/// `main.dart`'s `_AuthGateHost`).
///
/// On [LoginRegistrationSuccess] the [RegisterForm] swaps its
/// own body to the confirm-email prompt; on [LoginAuthenticated]
/// the [AuthGate] automatically tears this route out.
class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignConstants.backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DesignConstants.paddingBig),
          child: const RegisterForm(),
        ),
      ),
    );
  }
}
