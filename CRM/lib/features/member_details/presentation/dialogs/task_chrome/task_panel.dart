import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The ONE white lifted panel a nested staff dialog's content sits on — the
/// same object card the run behind it uses, at the compact dialog's own
/// padding.
///
/// One panel per dialog. A dialog that needs internal grouping uses
/// `FlowDetailGroup` (a hairline + a mono eyebrow) inside it; two panels read
/// as two unrelated forms, which is exactly what these dialogs are not.
///
/// [fill] takes the whole height the host gives it, so a list inside can use
/// `Expanded` and scroll against the fold rather than against a fixed box.
class TaskPanel extends StatelessWidget {
  final List<Widget> children;

  /// Fill the bounded height the host hands down instead of hugging.
  final bool fill;

  const TaskPanel({
    super.key,
    required this.children,
    this.fill = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        border: Border.all(color: DesignConstants.line),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: children,
      ),
    );
  }
}
