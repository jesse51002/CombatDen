import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';

/// Small secondary-color label, used for graph thresholds, axis annotations,
/// and similar overlays.
class ThresholdLabel extends StatelessWidget {
  const ThresholdLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: DesignConstants.p.copyWith(color: DesignConstants.text3rd),
    );
  }
}
