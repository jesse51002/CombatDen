import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/class_row/class_meta_chip.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';

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

  /// Recorded attendance for this occurrence; only shown (as "M attended")
  /// once [occurrenceInPast] — see [signupCount] for the always-shown
  /// headcount.
  final int? attendeeCount;

  /// Members signed up (reserved) for this occurrence — shown for both
  /// future AND past occurrences.
  final int? signupCount;

  /// True when this occurrence has already happened — the headcount chip
  /// then also shows [attendeeCount] ("M attended") alongside [signupCount].
  final bool occurrenceInPast;

  /// Marks a cancelled occurrence — shows a red "Cancelled" badge.
  final bool isCancelled;

  /// Roomy type scale (name 16, caption 13) for spacious surfaces like the
  /// member check-in/reserve picker; the default keeps the schedule board's
  /// dense day-column sizes.
  final bool large;

  /// Marks this card as the current pick on a selection surface (the member
  /// check-in dialog's occurrence cards): a primary border + check badge
  /// overlay and a `primaryColor10` wash — the same treatment
  /// `CheckInInstanceTile` gives a selected occurrence tile. Off by default
  /// (the schedule board and the class-identity pickers navigate on tap, no
  /// selected state).
  final bool selected;
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
    this.attendeeCount,
    this.signupCount,
    this.occurrenceInPast = false,
    this.isCancelled = false,
    this.large = false,
    this.selected = false,
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
          color: selected
              ? DesignConstants.primaryColor10
              : DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingMedium,
              children: [
                // Image bleeds to the full card width; the card clip handles
                // the corners, so the image itself has no separate rounding.
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
            // Overlaid (not part of the Column) so toggling selection never
            // shifts the card's layout.
            if (selected) ...[
              const Positioned.fill(child: _SelectedBorder()),
              const Positioned(
                top: DesignConstants.spacingMedium,
                right: DesignConstants.spacingMedium,
                child: _SelectedBadge(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The selected card's primary outline, painted over the content as a
/// non-interactive overlay.
class _SelectedBorder extends StatelessWidget {
  const _SelectedBorder();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: DesignConstants.primaryColor),
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        ),
      ),
    );
  }
}

/// The selected card's check mark, on a card-colored circle so it stays
/// legible over the class photo.
class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.spacingTiny),
      decoration: BoxDecoration(
        color: DesignConstants.card,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Symbols.check_circle_sharp,
        size: DesignConstants.iconSizeMedium,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.primaryColor,
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
        Text(
          card.name,
          style: card.large ? DesignConstants.h2 : DesignConstants.h3,
        ),
        Text(
          card.timeLabel,
          style: (card.large ? DesignConstants.h3Regular : DesignConstants.p)
              .copyWith(color: DesignConstants.text),
        ),
        if (card.isCancelled)
          ClassMetaChip(
            icon: Symbols.cancel_sharp,
            text: 'Cancelled',
            color: DesignConstants.badRed,
          ),
        if (card.instructorName != null) _InstructorLine(card: card),
        if (card.pointsWorth != null || card.signupCount != null)
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
    // Stacked, one chip per line — a narrow card can't fit
    // "N reserved · M attended" on a single line without overflowing.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        if (card.pointsWorth != null)
          ClassMetaChip(
            icon: Symbols.workspace_premium_sharp,
            text: '${card.pointsWorth} pts',
            color: DesignConstants.primaryColor,
          ),
        if (card.signupCount != null)
          ClassMetaChip(
            icon: Symbols.group_sharp,
            text: '${card.signupCount} reserved',
            color: DesignConstants.text2nd,
          ),
        if (card.signupCount != null && card.occurrenceInPast)
          ClassMetaChip(
            icon: Symbols.check_circle_sharp,
            text: '${card.attendeeCount ?? 0} attended',
            color: DesignConstants.text2nd,
          ),
      ],
    );
  }
}
