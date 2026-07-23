import 'package:flutter/material.dart';

import 'package:mobile_app/core/design_constants.dart';

/// Brand wordmark + screen title block shared by the login and register
/// screens. Dark-native, full-screen idiom (no card): a centered "CombatDen"
/// wordmark in the display font over a title + supporting subtitle.
class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingBig,
      children: [
        Text('CombatDen', style: DesignConstants.big2),
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
