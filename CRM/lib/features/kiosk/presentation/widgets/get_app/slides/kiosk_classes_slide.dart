import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_slide.dart';
import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

/// The showcase's `.bc-list` fits two rows before it crowds the slide box.
const int _kMaxRows = 2;

/// The row thumbnail's width; its height follows the 16:9 class-image ratio.
const double _kThumbWidth = 96.0;
const double _kThumbAspect = 16 / 9;

/// Slide 1 — "Book classes": an illustration of the member app's booking row.
///
/// **Data source: the gym's REAL classes.** The rows render
/// [EffectiveClassInstance]s the flow already loaded for this member (today's
/// occurrences open for check-in) — real class names, real gym-local start
/// times, real class images. Nothing here is invented; the mockup's "Muay Thai
/// Fundamentals / Boxing Conditioning" rows are demo content that on a
/// member-facing kiosk would read as this gym's schedule.
///
/// The slide is only built when the flow really holds classes — from the idle
/// home, before any member picked one, there are none and the slide is omitted
/// entirely (see `kioskShowcaseSlides`), so [classes] here is always populated.
///
/// The row anatomy is the MOBILE APP's booking row (thumb, name, when, Book
/// pill), not a CRM list row — it is a picture of the app being marketed, so
/// it does not reuse `ClassRow`/`ClassCard`, which are admin surfaces.
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

/// One class as the app's booking row (mockup `.bc-row`).
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
                _WhenLine(time: occurrence.resolvedClassTime),
              ],
            ),
          ),
          const _BookPill(),
        ],
      ),
    );
  }
}

/// "**Today** · 6:00 PM" — the cubit only ever loads today's occurrences, so
/// the day word is a fact, not a guess.
class _WhenLine extends StatelessWidget {
  final String time;

  const _WhenLine({required this.time});

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
            text: 'Today',
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
        // A decorative glyph, not words — the kiosk's AA text floor doesn't
        // reach it, and it should stay quieter than the class name beside it.
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

/// The app's Book affordance, shown as art — inert here (the kiosk books
/// nothing; the member books in the app).
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
