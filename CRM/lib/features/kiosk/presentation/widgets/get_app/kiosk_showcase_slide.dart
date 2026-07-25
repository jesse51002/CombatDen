import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/measured_max_width.dart';

/// One slide of the welcome showcase: the [title] the panel head rotates to
/// (and the dot's label), plus the [body] it fades in.
class KioskShowcaseSlide {
  final String title;
  final Widget body;

  const KioskShowcaseSlide({required this.title, required this.body});
}

/// A slide's centred stack: its content over the muted one-line caption.
/// [caption] is optional — the rewards slide speaks for itself.
///
/// There is deliberately no "nothing to show" variant: a slide the kiosk
/// cannot back up with the gym's real data is never built at all — see
/// `kioskShowcaseSlides`.
class KioskSlideBody extends StatelessWidget {
  final Widget content;
  final String? caption;

  const KioskSlideBody({super.key, required this.content, this.caption});

  @override
  Widget build(BuildContext context) {
    final line = caption;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        Flexible(child: content),
        if (line != null)
          // MeasuredMaxWidth, not ConstrainedBox: inside the welcome grid's
          // IntrinsicHeight a plain cap reports its height at the full panel
          // width (see that widget).
          MeasuredMaxWidth(
            maxWidth: DesignConstants.kioskGlanceMeasure,
            child: Text(
              line,
              style: DesignConstants.kioskCaption.copyWith(
                color: DesignConstants.text2nd,
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}
