import 'package:flutter/material.dart';
import 'package:crm/core/constants/design_constants.dart';

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
      children: [
        Text(
          title,
          style: DesignConstants.h1,
          textAlign: TextAlign.center,
        ),
        SizedBox(height: DesignConstants.spacingMedium.toDouble()),
        Text(
          subtitle,
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
