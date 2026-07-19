import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_step.dart';

/// Horizontal progress bar across the wizard's top-level groups. Completed
/// groups read done (green), the active group is emphasised, and its bar
/// splits into one mini-segment per substep so progress within the group
/// stays visible.
///
/// When [showAddMemberGroup] is true a leading always-completed "Add member"
/// segment is prepended (the add-member flow). A null [step] means the flow is
/// on its own add-member phases (before the wizard mounts) — the add-member
/// group renders ACTIVE and the rest upcoming; once the wizard is running a
/// non-null [step] makes add-member done and `step.group` active.
class StartMembershipsStepIndicator
    extends StatelessWidget {
  final StartMembershipsStep? step;
  final bool showAddMemberGroup;

  const StartMembershipsStepIndicator({
    super.key,
    required this.step,
    this.showAddMemberGroup = false,
  });

  List<StartMembershipsStepGroup> get _groups {
    final all = StartMembershipsStepGroup.values;
    if (showAddMemberGroup) return all;
    return all
        .where((g) => g != StartMembershipsStepGroup.addMember)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    final activeIndex = step == null
        // The flow's own add-member phases: the add-member group is active.
        ? groups.indexOf(StartMembershipsStepGroup.addMember)
        : groups.indexOf(step!.group);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      spacing: DesignConstants.spacingLarge,
      children: [
        for (var i = 0; i < groups.length; i++)
          Expanded(
            child: _GroupSegment(
              number: i + 1,
              group: groups[i],
              done: i < activeIndex,
              active: i == activeIndex,
              substepIndex: i == activeIndex
                  ? (step?.substepIndex ?? 0)
                  : 0,
            ),
          ),
      ],
    );
  }
}

/// One indicator segment: the group's progress bar with its
/// numbered title beneath. The active group's bar renders
/// one mini-bar per substep (reached = filled); done and
/// upcoming groups keep a single solid bar.
class _GroupSegment extends StatelessWidget {
  final int number;
  final StartMembershipsStepGroup group;
  final bool done;
  final bool active;
  final int substepIndex;

  const _GroupSegment({
    required this.number,
    required this.group,
    required this.done,
    required this.active,
    required this.substepIndex,
  });

  Color get _color => active
      ? DesignConstants.primaryColor
      : done
          ? DesignConstants.goodGreen
          : DesignConstants.text3rd;

  String get _stateLabel => active
      ? 'current step'
      : done
          ? 'completed'
          : 'upcoming';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step $number, ${group.title}, $_stateLabel',
      excludeSemantics: true,
      child: Column(
        spacing: DesignConstants.spacingSmall,
        children: [
          if (active && group.substepCount > 1)
            Row(
              spacing: DesignConstants.spacingTiny,
              children: [
                for (var i = 0;
                    i < group.substepCount;
                    i++)
                  Expanded(
                    child: _Bar(
                      color: i <= substepIndex
                          ? _color
                          : DesignConstants.text3rd,
                    ),
                  ),
              ],
            )
          else
            _Bar(color: _color),
          Text(
            '$number · ${group.title}',
            style: active
                ? DesignConstants.pSmallSemibold
                    .copyWith(color: _color)
                : DesignConstants.pSmall
                    .copyWith(color: _color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// The indicator's 4px rounded bar primitive.
class _Bar extends StatelessWidget {
  final Color color;

  const _Bar({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DesignConstants.progressBarThickness,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
