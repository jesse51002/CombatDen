import 'package:flutter/material.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/animation/loading_dots.dart';

/// Full-screen branded boot state — the app's [LoadingDots] centered on the
/// canvas. Shown by the auth gate while the initial session / identity check
/// is in flight.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignConstants.backgroundColor,
      body: const Center(child: LoadingDots()),
    );
  }
}
