import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/memberships/data/models/membership_plan_price_with_count.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// One price-version row in the edit-mode price section: the amount, how
/// many members are on it, and — for an older version — a Migrate button
/// that moves members onto the current price. The button is grayed when
/// there is no one to migrate (0 members) or a migration is already in
/// flight for this version.
class PlanPriceVersionRow extends StatelessWidget {
  final MembershipPlanPriceWithCount price;
  final bool isCurrent;
  final bool migrating;
  final VoidCallback? onMigrate;

  const PlanPriceVersionRow({
    super.key,
    required this.price,
    required this.isCurrent,
    this.migrating = false,
    this.onMigrate,
  });

  @override
  Widget build(BuildContext context) {
    // Current price reads as prominent (bold, full-strength border); older
    // versions are grayed out so the distinction is obvious at a glance.
    final priceColor =
        isCurrent ? DesignConstants.text : DesignConstants.text2nd;
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        border: Border.all(
          color: isCurrent ? DesignConstants.primaryColor : DesignConstants.line,
          width: isCurrent ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingTiny,
              children: [
                Text(
                  formatMinorUnits(price.price),
                  style: DesignConstants.pBig.copyWith(color: priceColor),
                ),
                Text(_subtitle, style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                )),
              ],
            ),
          ),
          if (isCurrent) _currentTag() else _migrateButton(),
        ],
      ),
    );
  }

  String get _subtitle {
    final members = '${price.memberCount} '
        'member${price.memberCount == 1 ? '' : 's'}';
    return isCurrent ? 'Current price · $members' : '$members on this price';
  }

  Widget _currentTag() {
    return Text(
      'Current',
      style: DesignConstants.pSmall.copyWith(
        color: DesignConstants.primaryColor,
      ),
    );
  }

  Widget _migrateButton() {
    final disabled = migrating || price.memberCount == 0 || onMigrate == null;
    return AppOutlineButton(
      text: migrating ? 'Migrating…' : 'Migrate',
      onPressed: disabled ? null : onMigrate,
      borderRadius: DesignConstants.radiusSmall,
      textStyle: DesignConstants.pSmall,
      // Gray the button out when there is nothing to migrate.
      borderColor: disabled ? DesignConstants.text2nd : DesignConstants.text,
      textColor: disabled ? DesignConstants.text2nd : DesignConstants.text,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.paddingSmall,
        vertical: DesignConstants.spacingSmall,
      ),
    );
  }
}
