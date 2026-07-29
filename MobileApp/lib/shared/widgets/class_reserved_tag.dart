import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:mobile_app/core/design_constants.dart';

/// The app's ONE mark for "the member holds this occurrence".
///
/// Used in both places a reserved class can be seen — the schedule board's
/// row and the class detail's meta block — so a reservation reads as the same
/// object wherever it appears. Never fork a second treatment for it.
///
/// It is `accent`-toned, not `primaryColor`: accent is the app's
/// selection / active-state colour ("where you are"), and a held reservation
/// is a state, not an action. That also keeps it from competing with the
/// footer's Reserve CTA, which owns the primary orange. Its surface recipe
/// (tinted fill + hairline border + glyph + label) is [ErrorMessage]'s, so the
/// screen's positive and negative statuses read as one system; only the
/// geometry differs — self-sizing pill, not a full-width banner, because this
/// is an attribute of the class, not an alert.
///
/// Status only: deliberately not tappable. Cancelling lives in the footer's
/// single, confirmed action.
class ClassReservedTag extends StatelessWidget {
  const ClassReservedTag({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = DesignConstants.accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(
          color: accent.withValues(alpha: 0.35),
          width: DesignConstants.dividerThickness,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingMedium,
          vertical: DesignConstants.spacingSmall,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingSmall,
          children: [
            Icon(
              Symbols.check_sharp,
              weight: DesignConstants.iconWeight,
              color: accent,
              size: DesignConstants.iconSizeSm,
            ),
            Text(
              'You\'re reserved',
              style: DesignConstants.h3.copyWith(color: accent),
            ),
          ],
        ),
      ),
    );
  }
}
