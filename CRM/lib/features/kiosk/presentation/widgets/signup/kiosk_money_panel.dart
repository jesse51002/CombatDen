import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_card_chip.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_money_labels.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_proration_note.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_two_charges_note.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';

/// The review's money half: what comes off the card today, itemised, on which
/// card, to which receipt address — then what happens next month.
///
/// **Every figure here is a field of the preview response.** The only
/// arithmetic is the due-today sum, and it lives on
/// [KioskSignupState.dueTodayMinorUnits] with its reasoning; nothing on this
/// screen derives a price from a plan row.
class KioskMoneyPanel extends StatelessWidget {
  final KioskSignupState state;

  /// Where payment mail reaches the payer — their own address. Empty when the
  /// payer carries none, which drops the line entirely.
  ///
  /// **No receipt is emailed.** CombatDen sends no mail at all (there is no
  /// mailer in the backend), and the connected account is set to notify a member
  /// on a FAILED payment only — so this line states the address a
  /// failure notice would reach, never a receipt. The unmasked address on a
  /// shared iPad is justified by exactly that: the payer confirming the address
  /// that has to work when a renewal fails.
  final String receiptEmail;

  const KioskMoneyPanel({
    super.key,
    required this.state,
    required this.receiptEmail,
  });

  @override
  Widget build(BuildContext context) {
    final receipt = receiptEmail.trim();
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
          Text('DUE TODAY', style: DesignConstants.kioskEyebrow),
          Text(
            formatMinorUnits(
              state.dueTodayMinorUnits,
              currency: state.currency,
            ),
            style: DesignConstants.kioskDisplay,
          ),
          _Lines(state: state),
          if (state.chargedProrated)
            KioskProrationNote(until: state.prorationUntil),
          if (state.chargedTwiceToday) const KioskTwoChargesNote(),
          KioskCardChip(brand: state.cardBrand, last4: state.cardLast4),
          // Unreachable blank in the ordinary flow: an email is required at the
          // details step. A payer adopted from the gym's own records can still
          // carry none, so the line is DROPPED rather than printed with a
          // trailing empty address. The results panel drops it the same way.
          if (receipt.isNotEmpty)
            Text(
              'If a payment ever fails, we\'ll email you at $receipt.',
              style: DesignConstants.kioskCaption.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          _Then(state: state),
        ],
      ),
    );
  }
}

/// The itemisation, so the one big number is visibly its parts — the one-time
/// invoice's lines first, then whatever is due now on the recurring side.
///
/// The line amount read is the invoice line's own `amount`. That is the same
/// figure the backend charges here, because a kiosk cart carries nothing that
/// could reduce a line below it.
///
/// **A group's lines are labelled BY PERSON** ("Ella · Kids Program"),
/// attributed through the line's own `stripe_price_id`. The amount stays the
/// preview's — a price is never derived from a plan row, and a shared price is
/// named for everyone on it rather than split.
class _Lines extends StatelessWidget {
  final KioskSignupState state;

  const _Lines({required this.state});

  @override
  Widget build(BuildContext context) {
    final lines = <PreviewInvoiceLine>[
      ...?state.preview?.oneTime?.lines,
      ...?state.preview?.dueNow?.lines,
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        for (final line in lines)
          Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              Expanded(
                child: Text(
                  kioskLineLabel(state, line) ??
                      line.description ??
                      'Membership',
                  style: DesignConstants.kioskCaption.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                formatMinorUnits(line.amount, currency: state.currency),
                style: DesignConstants.kioskCaption,
              ),
            ],
          ),
      ],
    );
  }
}

/// What happens after today — the steady-state per-cycle amount and the date
/// it first bills, both straight off the preview's recurring half. A purely
/// one-time cart has no recurring half, so nothing is claimed at all.
class _Then extends StatelessWidget {
  final KioskSignupState state;

  const _Then({required this.state});

  static final DateFormat _next = DateFormat('d MMMM y');

  @override
  Widget build(BuildContext context) {
    final recurring = state.preview?.recurring;
    if (recurring == null) return const SizedBox.shrink();
    final at = recurring.nextPaymentAt;
    final cycle = _cycleWord(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          'Then ${formatMinorUnits(recurring.total, currency: state.currency)}'
          ' each $cycle',
          style: DesignConstants.kioskLabel,
        ),
        Text(
          _detail(at),
          style: DesignConstants.kioskCaption.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }

  /// Who recurs and from when. In a group the names matter: a one-off pack
  /// does not recur for the child who got it, and letting the parent assume it
  /// does is the small lie that produces a phone call.
  String _detail(DateTime? at) {
    const tail = 'On the same card. Cancel any time at the front desk — no '
        'notice period.';
    final when = at == null ? null : _next.format(at.toLocal());
    final names = state.isGroup ? kioskRecurringNames(state) : const <String>[];
    final who = names.isEmpty ? null : kioskNameList(names);
    if (who != null && when != null) {
      return '$who, from $when. $tail';
    }
    if (who != null) return '$who. $tail';
    if (when != null) return 'Next charge $when. $tail';
    return tail;
  }

  /// The recurring plan's own billing unit, so "each month" is never asserted
  /// about a weekly or yearly plan. It reads the FIRST recurring plan in the
  /// cart rather than the active person's — at the review nobody is "active",
  /// and a non-training payer has no plan of their own at all.
  String _cycleWord(KioskSignupState state) {
    final plan = _recurringPlan(state);
    if (plan == null) return 'cycle';
    final unit = plan.durationUnit?.displayLabel.toLowerCase();
    final amount = plan.durationAmount ?? 1;
    if (unit == null || unit == 'unknown') return 'cycle';
    return amount == 1 ? unit : '$amount ${unit}s';
  }

  MembershipPlanResponse? _recurringPlan(KioskSignupState state) {
    for (final person in state.persons) {
      if (!person.training) continue;
      final plan = state.planById(person.selectedPlanId);
      if (plan?.planType == PlanType.recurring) return plan;
    }
    return null;
  }
}
