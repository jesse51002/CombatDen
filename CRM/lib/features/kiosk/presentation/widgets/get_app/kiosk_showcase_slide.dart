import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// One slide of the welcome showcase: the [title] the panel head rotates to
/// (and the dot's label), plus the [body] it fades in.
class KioskShowcaseSlide {
  final String title;
  final Widget body;

  const KioskShowcaseSlide({required this.title, required this.body});
}

/// A slide's centred stack: its content over the muted one-line caption
/// (mockup `.slide`/`.slide-copy`). [caption] is optional — the rewards slide
/// speaks for itself.
///
/// Every slide's content is the gym's REAL data. There is deliberately no
/// "nothing to show" variant here: a slide the kiosk cannot back up is never
/// built (see `kioskShowcaseSlides`), because on a member-facing screen a
/// stand-in would read as the gym's own schedule, catalogue, feed or belts.
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
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DesignConstants.kioskGlanceMeasure,
            ),
            child: Text(
              line,
              style: DesignConstants.pBig.copyWith(
                color: DesignConstants.text2nd,
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}
