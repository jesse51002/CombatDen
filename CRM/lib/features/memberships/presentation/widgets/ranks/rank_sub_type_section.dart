import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_bloc.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_event.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_state.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';

/// Chooses whether belts have sub-positions and how they're labelled —
/// **None** (belts only, no stripes/divisions), **Stripes**
/// (`1 Stripe`, `2 Stripes`, …) or **Divisions** (`Div 1`, `Div 2`, …).
/// The choice drives every sub-rank label across the ladder, member
/// detail, and the promotion dialog; it never stores a label per row.
/// Picking **None** turns sub-positions off gym-wide (members drop to no
/// sub-index server-side).
class RankSubTypeSection extends StatelessWidget {
  final RanksLoaded state;

  const RankSubTypeSection({super.key, required this.state});

  void _select(BuildContext context, RankSubType type) {
    if (type == state.subRankType) return;
    context.read<RanksBloc>().add(
          RankSubTypeChanged(gymId: state.gymId, type: type),
        );
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(DesignConstants.paddingSmall),
        child: Row(
          spacing: DesignConstants.spacingLarge,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Text('Sub-rank style', style: DesignConstants.h2),
                  Text(
                    'Whether belts have positions inside them, and how '
                    'they are labelled.',
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                ],
              ),
            ),
            _Segmented(
              current: state.subRankType,
              enabled: !state.isMutating,
              onSelected: (t) => _select(context, t),
            ),
          ],
        ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  final RankSubType current;
  final bool enabled;
  final ValueChanged<RankSubType> onSelected;

  const _Segmented({
    required this.current,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignConstants.backgroundAlt,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(color: DesignConstants.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DesignConstants.spacingTiny),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingTiny,
          children: [
            _Option(
              label: 'None',
              selected: current == RankSubType.none,
              enabled: enabled,
              onTap: () => onSelected(RankSubType.none),
            ),
            _Option(
              label: 'Stripes',
              selected: current == RankSubType.stripes,
              enabled: enabled,
              onTap: () => onSelected(RankSubType.stripes),
            ),
            _Option(
              label: 'Divisions',
              selected: current == RankSubType.div,
              enabled: enabled,
              onTap: () => onSelected(RankSubType.div),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _Option({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: selected ? DesignConstants.primaryColor : Colors.transparent,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        child: InkWell(
          onTap: enabled && !selected ? onTap : null,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignConstants.paddingSmall,
              vertical: DesignConstants.spacingMedium,
            ),
            child: Text(
              label,
              style: DesignConstants.h3.copyWith(
                color: selected
                    ? DesignConstants.onAccent
                    : DesignConstants.text2nd,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
