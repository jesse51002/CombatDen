import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/showcase/home/home_class.dart';
import 'package:crm/showcase/showcase_assets.dart';
import 'package:crm/showcase/showcase_tokens.dart';

const double _kClassImageWidth = 122;
const double _kClassImageHeight = 73;

/// Clone of MobileApp's `ClassListItem`. The class photo is a bundled asset
/// (the real app loads it from the network); the tap is a preview no-op.
class ClassListItem extends StatelessWidget {
  const ClassListItem({
    super.key,
    required this.classData,
    this.showBookings = true,
  });

  final ShowcaseClass classData;
  final bool showBookings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: ShowcaseTokens.spacingLarge,
      children: [
        InkWell(
          onTap: () {},
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ShowcaseTokens.screenHorizontalPadding,
              vertical: ShowcaseTokens.spacingMedium,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: ShowcaseTokens.spacingLarge,
              children: [
                Expanded(
                  child: _ClassInfo(
                    classData: classData,
                    showBookings: showBookings,
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(
                    ShowcaseTokens.radiusSmall,
                  ),
                  child: Image(
                    image: ShowcaseAsset.imageOrNetwork(
                      classData.imageUrl,
                      classData.imageAsset ?? '',
                    ),
                    width: _kClassImageWidth,
                    height: _kClassImageHeight,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => SizedBox(
                      width: _kClassImageWidth,
                      height: _kClassImageHeight,
                      child: ColoredBox(color: ShowcaseTokens.card),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          height: ShowcaseTokens.buttonBorder,
          color: ShowcaseTokens.divider,
        ),
      ],
    );
  }
}

class _ClassInfo extends StatelessWidget {
  const _ClassInfo({required this.classData, required this.showBookings});
  final ShowcaseClass classData;
  final bool showBookings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: ShowcaseTokens.spacingMedium,
      children: [
        Text(classData.name, style: ShowcaseTokens.h3),
        Text(
          '${classData.timeRange} (${classData.durationMinutes} min)',
          style: ShowcaseTokens.p,
        ),
        Text(
          classData.mentor,
          style: ShowcaseTokens.p.copyWith(color: ShowcaseTokens.text2nd),
        ),
        if (classData.attending != null)
          _BookedCount(count: classData.attending!),
        if (showBookings && classData.isBooked) const _BookedConfirmation(),
      ],
    );
  }
}

class _BookedConfirmation extends StatelessWidget {
  const _BookedConfirmation();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: ShowcaseTokens.spacingSmall,
      children: [
        Icon(
          Symbols.check_sharp,
          weight: ShowcaseTokens.iconWeight,
          color: ShowcaseTokens.text,
          size: ShowcaseTokens.iconSizeXs,
        ),
        Text('You booked this class!', style: ShowcaseTokens.h3),
      ],
    );
  }
}

class _BookedCount extends StatelessWidget {
  const _BookedCount({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: ShowcaseTokens.spacingSmall,
      children: [
        Icon(
          Symbols.person_sharp,
          weight: ShowcaseTokens.iconWeight,
          color: ShowcaseTokens.text2nd,
          size: ShowcaseTokens.iconSizeXs,
        ),
        Text(
          '$count attending',
          style: ShowcaseTokens.p.copyWith(color: ShowcaseTokens.text2nd),
        ),
      ],
    );
  }
}
