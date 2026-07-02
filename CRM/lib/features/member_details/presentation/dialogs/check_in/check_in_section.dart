import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/check_in_instance_tile.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/check_in_reserve_selection.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

/// One labelled, single-[action] section of pickable occurrences in the
/// check-in/reserve dialog — the class-scoped occurrence steps: a picked
/// class's past occurrences (a retroactive check-in) or its upcoming
/// occurrences (a reservation). (The Check-in view's CURRENT step renders
/// image cards via `CheckInOccurrenceCardGrid` instead, sharing [keyFor].)
/// Renders [emptyLabel] when [instances] is empty so a section that should
/// always communicate state can; the parent simply omits an empty optional
/// section instead.
class CheckInSection extends StatelessWidget {
  final String title;
  final CheckInReserveAction action;
  final List<EffectiveClassInstance> instances;
  final String? selectedKey;
  final ValueChanged<CheckInReserveSelection> onSelect;
  final String? emptyLabel;

  /// Off in the class-scoped occurrence steps — the section title already
  /// names the class, so tiles show only their date/time.
  final bool showClassName;

  const CheckInSection({
    super.key,
    required this.title,
    required this.action,
    required this.instances,
    required this.onSelect,
    this.selectedKey,
    this.emptyLabel,
    this.showClassName = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(title, style: DesignConstants.h2),
        if (instances.isEmpty && emptyLabel != null)
          Text(
            emptyLabel!,
            style: DesignConstants.h3Regular.copyWith(
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
                    selected: keyFor(action, i) == selectedKey,
                    showClassName: showClassName,
                    onTap: () => onSelect(
                      CheckInReserveSelection(instance: i, action: action),
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  /// A class can recur across the load window AND — since Check-in and
  /// Reserve intentionally overlap for an occurrence starting within the
  /// check-in window — the SAME occurrence can appear in two sections at
  /// once. The composite key is (action, classId, originalDate, originalTime)
  /// — the occurrence's full IDENTITY key (several slots per day are legal),
  /// not just the occurrence, so only the actually-picked tile (in its picked
  /// section) highlights.
  static String keyFor(CheckInReserveAction action, EffectiveClassInstance i) =>
      '${action.name}:${i.classId}@${i.originalDate.toIso8601String()}'
      '@${i.originalTime}';
}
