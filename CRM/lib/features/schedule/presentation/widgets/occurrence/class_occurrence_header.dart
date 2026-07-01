import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

final DateFormat _dateLabel = DateFormat('EEEE, MMM d, yyyy');

/// Aspect ratio of the class-image banner atop the occurrence screen — the
/// same 16:9 the board's `ClassCard` uses (`_kCardImageAspect` in
/// `lib/shared/widgets/class_row/class_card.dart`), so a class's image reads
/// consistently between the board card and this screen.
const double _kBannerAspect = 16 / 9;

/// The occurrence screen's header: the class image (when the class has one) as
/// a banner on top, then a back arrow, the class name, and the tapped
/// occurrence's date (e.g. "Tuesday, Jun 30, 2026") as a subtitle.
class ClassOccurrenceHeader extends StatelessWidget {
  final String className;
  final DateTime date;

  /// The class's image (the gym feed); a banner shows when set + non-empty.
  final String? imageUrl;
  final VoidCallback onBack;

  const ClassOccurrenceHeader({
    super.key,
    required this.className,
    required this.date,
    required this.onBack,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (imageUrl != null && imageUrl!.isNotEmpty)
          _Banner(imageUrl: imageUrl!),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingMedium,
          children: [
            InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
              child: Padding(
                padding: const EdgeInsets.all(DesignConstants.spacingSmall),
                child: Icon(
                  Symbols.arrow_back_sharp,
                  color: DesignConstants.text2nd,
                  weight: DesignConstants.iconWeight,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DesignConstants.spacingSmall,
                children: [
                  Text(
                    className,
                    style:
                        DesignConstants.h1.copyWith(color: DesignConstants.text),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _dateLabel.format(date),
                    style: DesignConstants.pBig
                        .copyWith(color: DesignConstants.text2nd),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Full-width rounded class-image banner at a fixed [_kBannerAspect]; a
/// placeholder shows if it fails.
class _Banner extends StatelessWidget {
  final String imageUrl;

  const _Banner({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: SizedBox(
        width: double.infinity,
        child: AspectRatio(
          aspectRatio: _kBannerAspect,
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const _BannerPlaceholder(),
          ),
        ),
      ),
    );
  }
}

class _BannerPlaceholder extends StatelessWidget {
  const _BannerPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DesignConstants.card,
      child: Center(
        child: Icon(
          Symbols.image_sharp,
          size: DesignConstants.iconSizeBig,
          color: DesignConstants.text3rd,
          weight: DesignConstants.iconWeight,
        ),
      ),
    );
  }
}
