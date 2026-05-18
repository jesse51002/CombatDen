import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// Centered title + supporting subtitle stack. Used at the top of full-bleed
/// content screens.
class AppHeadline extends StatelessWidget {
  const AppHeadline({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(title, style: DesignConstants.h1, textAlign: TextAlign.center),
        Text(
          subtitle,
          style: DesignConstants.h3.copyWith(color: DesignConstants.text2nd),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
