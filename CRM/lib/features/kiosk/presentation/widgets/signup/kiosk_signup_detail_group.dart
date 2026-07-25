import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// A named group of fields INSIDE a `KioskSignupFormPanel` — a hairline and a
/// mono eyebrow, the de-card treatment the kiosk uses for a group within a
/// surface (a second white panel would read as a second, unrelated form).
///
/// [eyebrow] is omitted for the first group: the screen's own title already
/// names it.
class KioskSignupDetailGroup extends StatelessWidget {
  final String? eyebrow;
  final List<Widget> children;

  const KioskSignupDetailGroup({
    super.key,
    required this.children,
    this.eyebrow,
  });

  @override
  Widget build(BuildContext context) {
    final word = eyebrow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (word != null) ...[
          const Hairline(),
          Text(word.toUpperCase(), style: DesignConstants.kioskEyebrow),
        ],
        ...children,
      ],
    );
  }
}
