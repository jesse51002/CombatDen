import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The app's standard inline loading spinner: a 24×24
/// [CircularProgressIndicator] in the brand primary.
///
/// Use this everywhere a small in-place spinner is needed instead of
/// re-typing `SizedBox(height: 24, width: 24, child: …)` — the size stays on
/// [DesignConstants.iconSizeLarge] in one place and can never re-drift.
class AppSpinner extends StatelessWidget {
  const AppSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DesignConstants.iconSizeLarge,
      width: DesignConstants.iconSizeLarge,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: DesignConstants.primaryColor,
      ),
    );
  }
}
