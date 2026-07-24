import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Two fields side by side, each taking half the panel — the mockup's 2-up
/// field grid.
///
/// It exists so both detail steps lay their pairs out identically: the
/// keyboard state's whole fold budget depends on the grid staying 2-up, so
/// which fields pair with which is a per-step decision but HOW they pair is
/// not.
class KioskSignupFieldPair extends StatelessWidget {
  final List<Widget> children;

  const KioskSignupFieldPair({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        for (final child in children) Expanded(child: child),
      ],
    );
  }
}
