import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/memberships/presentation/widgets/icon_option_cards.dart';

/// The three membership-type cards (Recurring / One Time / Trial),
/// rendered with the shared [IconOptionCards] selector.
class PlanTypeCards extends StatelessWidget {
  final PlanType selected;
  final ValueChanged<PlanType> onSelected;

  const PlanTypeCards({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  static const _types = [
    PlanType.recurring,
    PlanType.oneTime,
    PlanType.trial,
  ];

  @override
  Widget build(BuildContext context) {
    final index = _types.indexOf(selected);
    return IconOptionCards(
      options: const [
        IconOption(
          icon: Symbols.calendar_month_sharp,
          label: 'Recurring',
          subtitle: 'Billed monthly',
        ),
        IconOption(
          icon: Symbols.attach_money_sharp,
          label: 'One Time',
          subtitle: 'Single payment',
        ),
        IconOption(
          icon: Symbols.card_giftcard_sharp,
          label: 'Trial',
          subtitle: 'Limited-time',
        ),
      ],
      selectedIndex: index < 0 ? 0 : index,
      onSelected: (i) => onSelected(_types[i]),
    );
  }
}
