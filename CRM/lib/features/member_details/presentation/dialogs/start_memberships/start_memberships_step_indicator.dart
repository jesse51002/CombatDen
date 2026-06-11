import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_step.dart';

/// Horizontal progress bar across the wizard's three
/// top-level groups (Select payer · Select memberships ·
/// Confirmation). Completed groups read done (green), the
/// active group is emphasised, and its bar splits into one
/// mini-segment per substep so progress within the group
/// stays visible without eight flat labels.
class StartMembershipsStepIndicator
    extends StatelessWidget {
  final StartMembershipsStep step;

  const StartMembershipsStepIndicator({
    super.key,
    required this.step,
  });

  @override
  Widget build(BuildContext context) {
    final groups = StartMembershipsStepGroup.values;
    final activeIndex = groups.indexOf(step.group);
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
                  ? step.substepIndex
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

  @override
  Widget build(BuildContext context) {
    return Column(
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
      height: 4,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
