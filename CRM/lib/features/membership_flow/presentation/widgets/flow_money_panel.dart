import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/models/flow_money_view.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_card_chip.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_proration_note.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_two_charges_note.dart';

/// The review's money half: what comes off the card today, itemised, on which
/// card, to which address — then what happens next month.
///
/// Every figure here is a field of the preview response, in minor units,
/// formatted only at render. Nothing on this panel derives a price from a plan
/// row, and nothing here does arithmetic — the host hands it the answer.
class FlowMoneyPanel extends StatelessWidget {
  final FlowMoneyView money;

  /// Where payment mail reaches the payer. Empty drops the line entirely.
  ///
  /// No receipt is emailed — CombatDen has no mailer, and the connected
  /// account notifies on a FAILED payment only — so this line may only promise
  /// a failure notice. That is also what justifies an unmasked address on a
  /// shared iPad: the payer confirming what has to work when a renewal fails.
  final String contactEmail;

  /// A control over HOW today's first period is charged, slotted between the
  /// itemisation and the notes that explain it.
  ///
  /// A SLOT rather than a parameter set, for the same reason the discounts
  /// capability is an object: a surface that does not offer the choice has
  /// nothing to pass, so the control is absent rather than disabled. The kiosk
  /// pins `prorate_to_anchor` and passes null; the desk hands staff the pair,
  /// and the panel's own proration note lands directly beneath it, which is
  /// what makes the choice legible as it moves the total above.
  final Widget? firstPeriod;

  /// What the recurring half is MADE of, under its headline — the desk's
  /// itemisation of what this run adds versus what the payer already pays.
  /// Null on a surface that states the total and stops there.
  final Widget? recurringBreakdown;

  const FlowMoneyPanel({
    super.key,
    required this.money,
    required this.contactEmail,
    this.firstPeriod,
    this.recurringBreakdown,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final copy = MembershipFlowTheme.copyOf(context);
    final contact = contactEmail.trim();
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        border: Border.all(color: DesignConstants.line),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(copy.dueTodayEyebrow, style: scale.eyebrow),
          Text(
            formatMinorUnits(
              money.dueTodayMinorUnits,
              currency: money.currency,
            ),
            style: scale.total,
          ),
          _Lines(money: money),
          ?firstPeriod,
          if (money.prorated) FlowProrationNote(until: money.prorationUntil),
          if (money.chargedTwiceToday) const FlowTwoChargesNote(),
          FlowCardChip(brand: money.cardBrand, last4: money.cardLast4),
          // An email is required at the details step, but a payer adopted from
          // the gym's own records can carry none — so the line is DROPPED
          // rather than printed with a trailing empty address.
          if (contact.isNotEmpty)
            Text(
              copy.failedPaymentNotice(contact),
              style: scale.caption.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          _Then(money: money, breakdown: recurringBreakdown),
        ],
      ),
    );
  }
}

/// The itemisation, so the one big number is visibly its parts — the one-time
/// invoice's lines first, then whatever is due now on the recurring side.
///
/// Each amount is the invoice line's own `amount` — exactly what the backend
/// charges. A group's lines are labelled BY PERSON by the host; only the label
/// is ever derived, never the money.
class _Lines extends StatelessWidget {
  final FlowMoneyView money;

  const _Lines({required this.money});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    if (money.lines.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        for (final line in money.lines)
          Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              Expanded(
                child: Text(
                  line.label,
                  style: scale.caption.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                formatMinorUnits(
                  line.amountMinorUnits,
                  currency: money.currency,
                ),
                style: scale.caption,
              ),
            ],
          ),
      ],
    );
  }
}

/// What happens after today — the per-cycle amount and the date it first
/// bills, straight off the preview's recurring half. A purely one-time cart
/// has no recurring half, so nothing is claimed at all.
class _Then extends StatelessWidget {
  final FlowMoneyView money;

  /// The host's own itemisation of the recurring half, under the headline.
  final Widget? breakdown;

  const _Then({required this.money, this.breakdown});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final copy = MembershipFlowTheme.copyOf(context);
    final recurring = money.recurring;
    if (recurring == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          copy.recurringHeadline(
            totalMinorUnits: recurring.totalMinorUnits,
            currency: money.currency,
            cycleWord: recurring.cycleWord,
          ),
          style: scale.label,
        ),
        Text(
          copy.recurringDetail(
            names: recurring.names,
            nextPaymentAt: recurring.nextPaymentAt,
          ),
          style: scale.caption.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        ?breakdown,
      ],
    );
  }
}
