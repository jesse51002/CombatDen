import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/models/class_occurrence.dart';
import 'package:mobile_app/features/qr_checkin/presentation/widgets/pick_class/pick_class_card.dart';

/// The scrollable list of today's pickable classes. Hairline dividers between
/// rows via `ListView.separated` (the idiomatic gap for a lazy list).
class PickClassList extends StatelessWidget {
  const PickClassList({
    super.key,
    required this.occurrences,
    required this.onPick,
  });

  final List<ClassOccurrence> occurrences;
  final ValueChanged<ClassOccurrence> onPick;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.symmetric(vertical: DesignConstants.spacingMedium),
      itemCount: occurrences.length,
      separatorBuilder: (_, _) => Container(
        height: DesignConstants.dividerThickness,
        color: DesignConstants.divider,
      ),
      itemBuilder: (context, index) => PickClassCard(
        occurrence: occurrences[index],
        onTap: onPick,
      ),
    );
  }
}
