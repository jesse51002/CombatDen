import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// The topbar's outer container: the separating rule and the screen
/// inset. Shared by every shell layout so the frame is defined once.
class TopbarFrame extends StatelessWidget {
  const TopbarFrame({
    super.key,
    required this.child,
    this.rule = true,
    this.compact = false,
  });

  final Widget child;
  final bool rule;

  /// Trades the tall stacked inset for a single-row one.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: rule
            ? Border(
                bottom: BorderSide(
                  color: DesignConstants.text3rd,
                  width: DesignConstants.dividerThickness,
                ),
              )
            : null,
      ),
      padding: EdgeInsets.only(
        top: compact ? DesignConstants.spacingLarge
            : DesignConstants.spacingBig,
        bottom: compact ? DesignConstants.spacingMedium
            : DesignConstants.spacingLarge,
        left: DesignConstants.spacingMedium,
        right: DesignConstants.spacingMedium,
      ),
      child: child,
    );
  }
}
