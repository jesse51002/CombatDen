import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Wordmark + screen title block shared by [LoginScreen] and
/// [RegisterScreen].
///
/// Renders the CombatDen logo + wordmark above a centered title
/// and optional subtitle, using the landing-aligned Geist type
/// tokens from [DesignConstants].
class AuthHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const AuthHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        _Wordmark(),
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(
              title,
              style: DesignConstants.h1,
              textAlign: TextAlign.center,
            ),
            Text(
              subtitle,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ],
    );
  }
}

class _Wordmark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        Image.asset(
          'assets/images/combatden_logo.png',
          height: DesignConstants.iconSizeBig,
        ),
        Text('CombatDen', style: DesignConstants.navWordmark),
      ],
    );
  }
}
