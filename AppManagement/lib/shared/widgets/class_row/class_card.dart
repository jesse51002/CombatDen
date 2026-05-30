import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/shared/widgets/class_row/class_meta_chip.dart';
import 'package:app_management/shared/widgets/class_row/instructor_avatar.dart';

/// Enforced image ratio for every class card, so a column of cards stays
/// visually uniform whether or not a class has its own image.
const double _kCardImageAspect = 16 / 9;

/// A class as a vertical card: image on top (fixed aspect ratio), then
/// name / time / instructor / metadata below. Used by the schedule board's
/// day columns.
class ClassCard extends StatelessWidget {
  final String name;
  final String timeLabel;
  final String? instructorName;

  /// Instructor photo: a network [instructorPhotoUrl] (the gym feed) is
  /// preferred, else a bundled [instructorPhotoAsset]; both optional.
  final String? instructorPhotoUrl;
  final String? instructorPhotoAsset;

  /// Class image: a network [imageUrl] (the gym feed) is preferred, else a
  /// bundled [imageAsset]; a placeholder shows when neither resolves.
  final String? imageUrl;
  final String? imageAsset;
  final int? pointsWorth;
  final int? attendingCount;
  final VoidCallback? onTap;

  const ClassCard({
    super.key,
    required this.name,
    required this.timeLabel,
    this.instructorName,
    this.instructorPhotoUrl,
    this.instructorPhotoAsset,
    this.imageUrl,
    this.imageAsset,
    this.pointsWorth,
    this.attendingCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: [
            // Image bleeds to the full card width; the card clip handles the
            // corners, so the image itself has no separate rounding.
            _CardImage(asset: imageAsset, imageUrl: imageUrl),
            Padding(
              padding: const EdgeInsets.only(
                left: DesignConstants.spacingMedium,
                right: DesignConstants.spacingMedium,
                bottom: DesignConstants.spacingMedium,
              ),
              child: _CardDetails(card: this),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardImage extends StatelessWidget {
  final String? asset;
  final String? imageUrl;
  const _CardImage({required this.asset, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _kCardImageAspect,
      child: _image(),
    );
  }

  Widget _image() {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _ImagePlaceholder(),
      );
    }
    if (asset != null) return Image.asset(asset!, fit: BoxFit.cover);
    return const _ImagePlaceholder();
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

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

class _CardDetails extends StatelessWidget {
  final ClassCard card;
  const _CardDetails({required this.card});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(card.name, style: DesignConstants.h3),
        Text(
          card.timeLabel,
          style: DesignConstants.p.copyWith(color: DesignConstants.text),
        ),
        if (card.instructorName != null) _InstructorLine(card: card),
        if (card.pointsWorth != null || card.attendingCount != null)
          _MetaRow(card: card),
      ],
    );
  }
}

class _InstructorLine extends StatelessWidget {
  final ClassCard card;
  const _InstructorLine({required this.card});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        InstructorAvatar(
          photoUrl: card.instructorPhotoUrl,
          photoAsset: card.instructorPhotoAsset,
          name: card.instructorName,
          diameter: 20,
        ),
        Expanded(
          child: Text(
            card.instructorName!,
            style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  final ClassCard card;
  const _MetaRow({required this.card});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: DesignConstants.spacingMedium,
      runSpacing: DesignConstants.spacingSmall,
      children: [
        if (card.pointsWorth != null)
          ClassMetaChip(
            icon: Symbols.workspace_premium_sharp,
            text: '${card.pointsWorth} pts',
            color: DesignConstants.primaryColor,
          ),
        if (card.attendingCount != null)
          ClassMetaChip(
            icon: Symbols.person_sharp,
            text: '${card.attendingCount} attending',
            color: DesignConstants.text2nd,
          ),
      ],
    );
  }
}
