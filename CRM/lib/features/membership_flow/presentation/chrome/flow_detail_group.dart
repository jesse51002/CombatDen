import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// A named group of fields INSIDE a `FlowFormPanel` — a hairline and a
/// mono eyebrow, the de-card treatment the kiosk uses for a group within a
/// surface (a second white panel would read as a second, unrelated form).
///
/// [eyebrow] is omitted for the first group: the screen's own title already
/// names it.
class FlowDetailGroup extends StatelessWidget {
  final String? eyebrow;
  final List<Widget> children;

  const FlowDetailGroup({
    super.key,
    required this.children,
    this.eyebrow,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final word = eyebrow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (word != null) ...[
          const Hairline(),
          Text(word.toUpperCase(), style: scale.eyebrow),
        ],
        ...children,
      ],
    );
  }
}
