import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/check_in_instance_tile.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

/// One labelled section of pickable occurrences in the check-in dialog — the
/// emphasized "Today" (Active) list and the secondary "Last 7 days" (Past)
/// list. Renders [emptyLabel] when [instances] is empty so the Active section
/// always communicates state; the parent simply omits an empty Past section.
class CheckInSection extends StatelessWidget {
  final String title;
  final List<EffectiveClassInstance> instances;
  final String? selectedClassDateKey;
  final ValueChanged<EffectiveClassInstance> onSelect;
  final String? emptyLabel;

  const CheckInSection({
    super.key,
    required this.title,
    required this.instances,
    required this.onSelect,
    this.selectedClassDateKey,
    this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(title, style: DesignConstants.h3),
        if (instances.isEmpty && emptyLabel != null)
          Text(
            emptyLabel!,
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingSmall,
            children: instances
                .map(
                  (i) => CheckInInstanceTile(
                    instance: i,
                    selected: _keyFor(i) == selectedClassDateKey,
                    onTap: () => onSelect(i),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  /// A class can recur across the window, so a (classId, classDate) pair — not
  /// the classId alone — identifies the selected occurrence.
  static String keyFor(EffectiveClassInstance i) => _keyFor(i);

  static String _keyFor(EffectiveClassInstance i) =>
      '${i.classId}@${i.classDate.toIso8601String()}';
}
