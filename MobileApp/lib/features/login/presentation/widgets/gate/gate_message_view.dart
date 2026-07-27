import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/buttons/app_outline_button.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// A full-screen, calm message state used by the gate for the no-membership
/// and offline outcomes: a glyph, a headline, supporting body, a primary
/// action, and a secondary action. All tokens from [DesignConstants].
class GateMessageView extends StatelessWidget {
  const GateMessageView({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  final IconData icon;
  final String title;
  final Widget body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      horizontalPadding: AppScreenHorizontalPadding.big,
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingBig,
            children: [
              Icon(
                icon,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.text3rd,
                size: DesignConstants.iconSize2xl,
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingMedium,
                children: [
                  Text(
                    title,
                    style: DesignConstants.h1,
                    textAlign: TextAlign.center,
                  ),
                  body,
                ],
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingMedium,
                children: [
                  AppPrimaryButton(
                    text: primaryLabel,
                    onPressed: onPrimary,
                    fullWidth: true,
                  ),
                  AppOutlineButton(
                    text: secondaryLabel,
                    onPressed: onSecondary,
                    fullWidth: true,
                    borderRadius: DesignConstants.radiusSmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The gate's error/info glyph set, so callers don't reach for `Symbols`
/// directly and stay on the sharp set.
class GateIcons {
  GateIcons._();

  static const IconData noMembership = Symbols.person_search_sharp;
  static const IconData offline = Symbols.cloud_off_sharp;
}
