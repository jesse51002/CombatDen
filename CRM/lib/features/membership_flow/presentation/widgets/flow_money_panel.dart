import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/domain/name_labels.dart';
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

  const FlowMoneyPanel({
    super.key,
    required this.money,
    required this.contactEmail,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
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
          Text('DUE TODAY', style: scale.eyebrow),
          Text(
            formatMinorUnits(
              money.dueTodayMinorUnits,
              currency: money.currency,
            ),
            style: scale.display,
          ),
          _Lines(money: money),
          if (money.prorated) FlowProrationNote(until: money.prorationUntil),
          if (money.chargedTwiceToday) const FlowTwoChargesNote(),
          FlowCardChip(brand: money.cardBrand, last4: money.cardLast4),
          // An email is required at the details step, but a payer adopted from
          // the gym's own records can carry none — so the line is DROPPED
          // rather than printed with a trailing empty address.
          if (contact.isNotEmpty)
            Text(
              'If a payment ever fails, we\'ll email you at $contact.',
              style: scale.caption.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          _Then(money: money),
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

  const _Then({required this.money});

  static final DateFormat _next = DateFormat('d MMMM y');

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final recurring = money.recurring;
    if (recurring == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          'Then ${formatMinorUnits(
            recurring.totalMinorUnits,
            currency: money.currency,
          )} each ${recurring.cycleWord}',
          style: scale.label,
        ),
        Text(
          _detail(recurring),
          style: scale.caption.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }

  /// Who recurs and from when. In a group the names matter: a one-off pack
  /// does not recur for the child who got it.
  String _detail(FlowRecurringView recurring) {
    const tail = 'On the same card. Cancel any time at the front desk — no '
        'notice period.';
    final at = recurring.nextPaymentAt;
    final when = at == null ? null : _next.format(at.toLocal());
    final who =
        recurring.names.isEmpty ? null : flowNameList(recurring.names);
    if (who != null && when != null) {
      return '$who, from $when. $tail';
    }
    if (who != null) return '$who. $tail';
    if (when != null) return 'Next charge $when. $tail';
    return tail;
  }
}
