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
            _Thumbnail(asset: imageAsset),
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
        ? DesignConstants.lightPrimary
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
  const _Thumbnail({required this.asset});

  @override
  Widget build(BuildContext context) {
    if (asset == null) return const SizedBox(width: 122, height: 73);
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Image.asset(asset!, width: 122, height: 73, fit: BoxFit.cover),
    );
  }
}
