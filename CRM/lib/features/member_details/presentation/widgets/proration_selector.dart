import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';

/// Two-option proration choice — replaces the old binary "prorate"
/// switch. Both options START the membership; they differ only in
/// whether a partial charge happens NOW. Each option spells out its
/// outcome and, when known, the billing anchor it runs to.
///
/// [anchorDate] is the next full-cycle billing date (the proration
/// target). Pass it when a preview has loaded it; null falls back to
/// generic "the next billing date" copy.
class ProrationSelector extends StatelessWidget {
  final ProrationBehavior value;
  final ValueChanged<ProrationBehavior> onChanged;
  final DateTime? anchorDate;

  const ProrationSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.anchorDate,
  });

  @override
  Widget build(BuildContext context) {
    final when =
        anchorDate == null ? 'the next billing date' : formatDay(anchorDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        _OptionCard(
          title: 'Prorate now',
          subtitle: 'Charge the partial period through $when.',
          selected: value == ProrationBehavior.prorateToAnchor,
          onTap: () => onChanged(ProrationBehavior.prorateToAnchor),
        ),
        _OptionCard(
          title: 'No charge now',
          subtitle:
              'Membership still starts — first full bill lands on $when.',
          selected: value == ProrationBehavior.noCharge,
          onTap: () => onChanged(ProrationBehavior.noCharge),
        ),
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _OptionCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Container(
        padding: const EdgeInsets.all(DesignConstants.spacingMedium),
        decoration: BoxDecoration(
          color: selected
              ? DesignConstants.primaryColor.withValues(alpha: 0.10)
              : DesignConstants.backgroundColor,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          border: Border.all(
            color: selected
                ? DesignConstants.primaryColor
                : DesignConstants.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              selected
                  ? Symbols.radio_button_checked_sharp
                  : Symbols.radio_button_unchecked_sharp,
              weight: DesignConstants.iconWeight,
              size: DesignConstants.iconSizeLarge,
              color: selected
                  ? DesignConstants.primaryColor
                  : DesignConstants.text2nd,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Text(title, style: DesignConstants.h3),
                  Text(
                    subtitle,
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
