import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Full-screen loading state — a centered [AppSpinner] on
/// the app ground. Shown by the auth gate while the initial
/// authentication / gym check is in flight, and by any flow
/// that needs a whole-screen wait.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignConstants.backgroundColor,
      body: const Center(child: AppSpinner()),
    );
  }
}
