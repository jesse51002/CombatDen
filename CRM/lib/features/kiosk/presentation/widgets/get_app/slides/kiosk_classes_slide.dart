import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_slide.dart';
import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

/// Two rows is what fits before the list crowds the slide box.
const int _kMaxRows = 2;

/// The row thumbnail's width; its height follows the 16:9 class-image ratio.
const double _kThumbWidth = 96.0;
const double _kThumbAspect = 16 / 9;

/// Slide 1 — "Book classes": the gym's next upcoming occurrences drawn as the
/// member app's booking row.
///
/// [classes] is the warmed `showcaseClasses`, never the check-in flow's list —
/// that one is narrowed to the check-in window and empties every evening, so a
/// slide driven by it would vanish at the hour the gym is busiest (see
/// `KioskFlowCubit._warmShowcaseClasses`).
///
/// The row anatomy is the MOBILE APP's booking row, not a CRM list row: this
/// is a picture of the app being marketed, so it does not reuse
/// `ClassRow`/`ClassCard`, which are admin surfaces.
class KioskClassesSlide extends StatelessWidget {
  final List<EffectiveClassInstance> classes;

  const KioskClassesSlide({super.key, required this.classes});

  @override
  Widget build(BuildContext context) {
    const caption = 'Reserve your spot before you arrive.';
    final shown = classes.take(_kMaxRows).toList();
    return KioskSlideBody(
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: DesignConstants.dialogMaxWidth,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [for (final c in shown) _BookRow(occurrence: c)],
        ),
      ),
      caption: caption,
    );
  }
}

/// One class as the app's booking row.
class _BookRow extends StatelessWidget {
  final EffectiveClassInstance occurrence;

  const _BookRow({required this.occurrence});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.spacingMedium),
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(color: DesignConstants.line),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          _Thumb(imageUrl: occurrence.imageUrl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingTiny,
              children: [
                Text(
                  occurrence.className,
                  style: DesignConstants.kioskLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                _WhenLine(
                  date: occurrence.classDate,
                  time: occurrence.resolvedClassTime,
                ),
              ],
            ),
          ),
          const _BookPill(),
        ],
      ),
    );
  }
}

/// "Today · 6:00 PM" — the day word is read off the occurrence's own date,
/// never assumed: the showcase looks a week ahead, so a fixed "Today" would
/// state something untrue about a real class on a member-facing screen.
class _WhenLine extends StatelessWidget {
  final DateTime date;
  final String time;

  const _WhenLine({required this.date, required this.time});

  @override
  Widget build(BuildContext context) {
    final base = DesignConstants.kioskMicro.copyWith(
      fontWeight: FontWeight.w500,
      color: DesignConstants.text2nd,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(
            text: classDayWordLabel(date),
            style: base.copyWith(
              color: DesignConstants.goodGreen,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: ' · ${classStartTimeLabel(time)}'),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String? imageUrl;

  const _Thumb({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: SizedBox(
        width: _kThumbWidth,
        height: _kThumbWidth / _kThumbAspect,
        child: url != null && url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _ThumbPlaceholder(),
              )
            : const _ThumbPlaceholder(),
      ),
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DesignConstants.backgroundAlt,
      child: Center(
        // Decorative, not words, so the kiosk's AA text floor doesn't apply.
        child: Icon(
          Symbols.image_sharp,
          size: DesignConstants.iconSizeMedium,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.text3rd,
        ),
      ),
    );
  }
}

/// The app's Book affordance as art — inert (the member books in the app).
class _BookPill extends StatelessWidget {
  const _BookPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingLarge,
        vertical: DesignConstants.spacingMedium,
      ),
      decoration: ShapeDecoration(
        gradient: DesignConstants.primaryGradient,
        shape: const StadiumBorder(),
        shadows: DesignConstants.buttonShadow,
      ),
      child: Text(
        'Book',
        style: DesignConstants.kioskMicro.copyWith(
          color: DesignConstants.onAccent,
        ),
      ),
    );
  }
}
