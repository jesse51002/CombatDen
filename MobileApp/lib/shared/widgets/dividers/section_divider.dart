import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// A horizontal full-bleed divider used between major page sections.
class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DesignConstants.dividerThickness,
      color: DesignConstants.text3rd,
    );
  }
}
