import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// The raised surface a reward card sits on: card fill, big radius, and
/// the clip that lets the image bleed to the rounded corners.
class RewardCardShell extends StatelessWidget {
  const RewardCardShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: child,
    );
  }
}
