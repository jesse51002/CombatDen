import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/class_row/class_meta_chip.dart';

/// A class as a horizontal stacked row: a left column of name / time /
/// instructor (with optional booked-count chip) and a right thumbnail.
/// Used by the home dashboard's Upcoming Classes list.
class ClassRow extends StatelessWidget {
  final String name;
  final String timeLabel;
  final String? instructorName;

  /// Thumbnail: a network [imageUrl] (the gym feed) is preferred, else a
  /// bundled [imageAsset]; an empty slot keeps the row's layout when neither
  /// resolves.
  final String? imageUrl;
  final String? imageAsset;

  /// Recorded attendance for this occurrence; only shown (as "M attended")
  /// once [occurrenceInPast] — see [signupCount] for the always-shown
  /// headcount.
  final int? attendeeCount;

  /// Members signed up (reserved) for this occurrence — shown for both
  /// future AND past occurrences.
  final int? signupCount;

  /// True when this occurrence has already happened — the headcount chip
  /// then also shows [attendeeCount] ("M attended") alongside [signupCount].
  /// The dashboard Upcoming Classes list is always upcoming, so it leaves
  /// this false.
  final bool occurrenceInPast;
  final int? checkedInCount;
  final bool inSession;
  final VoidCallback? onTap;

  const ClassRow({
    super.key,
    required this.name,
    required this.timeLabel,
    this.instructorName,
    this.imageUrl,
    this.imageAsset,
    this.attendeeCount,
    this.signupCount,
    this.occurrenceInPast = false,
    this.checkedInCount,
    this.inSession = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: DesignConstants.spacingMedium,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingLarge,
          children: [
            Expanded(child: _ClassDetails(row: this)),
            _Thumbnail(asset: imageAsset, imageUrl: imageUrl),
          ],
        ),
      ),
    );
  }
}

class _ClassDetails extends StatelessWidget {
  final ClassRow row;
  const _ClassDetails({required this.row});

  @override
  Widget build(BuildContext context) {
    final nameLabel =
        row.inSession ? '${row.name} (In Session)' : row.name;
    final nameColor = row.inSession
        ? DesignConstants.primaryColor
        : DesignConstants.text;
    final isLive = row.checkedInCount != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(nameLabel, style: DesignConstants.h3.copyWith(color: nameColor)),
        Text(
          row.timeLabel,
          style: DesignConstants.p.copyWith(color: DesignConstants.text),
        ),
        if (row.instructorName != null)
          Text(
            row.instructorName!,
            style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          ),
        if (isLive)
          ClassMetaChip(
            icon: Symbols.person_sharp,
            text: '${row.checkedInCount} checked in',
            color: DesignConstants.primaryColor,
          )
        // Stacked, one count per line — "N reserved · M attended" on one line
        // overflows a narrow card.
        else ...[
          if (row.signupCount != null)
            ClassMetaChip(
              icon: Symbols.group_sharp,
              text: '${row.signupCount} reserved',
              color: DesignConstants.text2nd,
            ),
          if (row.signupCount != null && row.occurrenceInPast)
            ClassMetaChip(
              icon: Symbols.check_circle_sharp,
              text: '${row.attendeeCount ?? 0} attended',
              color: DesignConstants.text2nd,
            ),
        ],
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final String? asset;
  final String? imageUrl;
  const _Thumbnail({required this.asset, required this.imageUrl});

  static const double _kWidth = 122;
  static const double _kHeight = 73;

  @override
  Widget build(BuildContext context) {
    final image = _image();
    if (image == null) {
      return const SizedBox(width: _kWidth, height: _kHeight);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: image,
    );
  }

  Widget? _image() {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Image.network(
        imageUrl!,
        width: _kWidth,
        height: _kHeight,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const SizedBox(width: _kWidth, height: _kHeight),
      );
    }
    if (asset != null) {
      return Image.asset(asset!, width: _kWidth, height: _kHeight,
          fit: BoxFit.cover);
    }
    return null;
  }
}
