import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/shared/widgets/class_row/class_meta_chip.dart';

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
  final int? attendingCount;
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
    this.attendingCount,
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
        else if (row.attendingCount != null)
          ClassMetaChip(
            icon: Symbols.person_sharp,
            text: '${row.attendingCount} attending',
            color: DesignConstants.text2nd,
          ),
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
