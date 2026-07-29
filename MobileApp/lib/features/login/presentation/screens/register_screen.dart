import 'package:flutter/material.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/login/presentation/widgets/register_form.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// Registration screen — full-screen, dark-native email + password + confirm
/// sign-up. Pushed from [LoginScreen] onto the unauthenticated flow's nested
/// navigator; shares the same [LoginBloc] from the tree.
class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScreenScaffold(
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            vertical: DesignConstants.paddingBig,
          ),
          child: RegisterForm(),
        ),
      ),
    );
  }
}
