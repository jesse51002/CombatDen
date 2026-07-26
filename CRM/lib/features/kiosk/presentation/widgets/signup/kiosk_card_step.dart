import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_card_facts.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_step_scaffold.dart';
import 'package:crm/features/member_details/presentation/dialogs/card_field_box.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_foot.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_form_panel.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_who_for.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_inline_notice.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_secure_strip.dart';

/// D5 — the card, and the trust screen around it.
///
/// The FRESH-CARD LAW: the kiosk never charges a card already on file. It
/// always collects a new one, which becomes the payer's Stripe default and
/// replaces theirs — so a later front-desk "charge the card on file" bills
/// whoever typed it here, and this step says so to the member. The card is
/// tokenized on the GYM's Stripe Connect connected account (a platform `pm_…`
/// cannot attach to a connected-account customer), and the kiosk holds only
/// the `pm_…` id plus brand/last-four — never card data, never a saved-card
/// list.
///
/// The field is the shipped [CardFieldBox] (founder ruling) — one payment
/// surface, not the mockup's four boxes. Nothing is charged here: the footer's
/// primary tokenizes and hands the `pm_…` to the cubit, and a tokenization
/// failure stays inline rather than ending the signup.
class KioskCardStep extends StatefulWidget {
  const KioskCardStep({super.key});

  @override
  State<KioskCardStep> createState() => _KioskCardStepState();
}

class _KioskCardStepState extends State<KioskCardStep> {
  /// Stripe's own completeness signal — the primary stays inert until the
  /// element says the card is whole, so "Review" never fires a doomed tokenize.
  bool _complete = false;
  bool _tokenizing = false;
  String? _error;

  Future<void> _review() async {
    if (!_complete || _tokenizing) return;
    setState(() {
      _tokenizing = true;
      _error = null;
    });
    try {
      final pm = await Stripe.instance.createPaymentMethod(
        params: const PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(),
        ),
      );
      if (!mounted) return;
      context.read<KioskSignupCubit>().submitCard(
            paymentMethodId: pm.id,
            brand: pm.card.brand,
            last4: pm.card.last4,
          );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tokenizing = false;
        _error = 'We couldn\'t read that card. Check the details and try '
            'again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    final gym = selectedGym.gymName;
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.cartHasRecurring != cur.cartHasRecurring ||
          prev.persons != cur.persons ||
          prev.selectedPlan != cur.selectedPlan ||
          // A retry bumps the attempt nonce; the field must re-key with it.
          prev.cardAttempt != cur.cardAttempt,
      builder: (context, state) {
        final payerName = _payerName(state);
        return KioskStepScaffold(
          step: KioskSignupStep.card,
          title: 'Your card',
          // In a group the "active person" is whoever signed last, so a plan
          // name here would be a fact about somebody who may not be paying.
          subtitle: state.isGroup ? null : state.selectedPlan?.planName,
          // The PAYER, never the active person (in a family, usually a child):
          // this is the profile the card lands on, so it has to be pinned.
          identity: payerName.isEmpty
              ? null
              : FlowWhoFor(eyebrow: 'CARD FOR', name: payerName),
          foot: FlowFoot(
            primaryLabel: 'Review',
            onPrimary: _complete && !_tokenizing ? _review : null,
            onBack: _tokenizing ? null : cubit.back,
            // Real work would die here, so leaving ASKS first — the card and
            // the review are the only two steps that confirm.
            onEscape: cubit.askAbandon,
          ),
          child: FlowFormPanel(
            children: [
              FlowSecureStrip(gymName: gym),
              CardFieldBox(
                // A fresh, empty Stripe iframe per attempt: `retryCard()` bumps
                // `cardAttempt` so this re-keys, otherwise the cached field
                // still holds the declined card and cannot be retyped.
                fieldKey: ValueKey('kiosk-card-${state.cardAttempt}'),
                onComplete: (isComplete) {
                  if (isComplete != _complete) {
                    setState(() => _complete = isComplete);
                  }
                },
              ),
              if (_error != null) _CardError(message: _error!),
              // Deliberately heavier than the ticked facts below it: what
              // happens to the card is something to REGISTER, not a
              // reassurance.
              FlowInlineNotice(message: _savedCardNotice(payerName)),
              KioskCardFacts(hasRecurring: state.cartHasRecurring),
            ],
          ),
        );
      },
    );
  }

  /// The person this card attaches to — read off the roster's payer seat, so
  /// it is right whether that is the person standing there or an existing
  /// member picked to pay.
  String _payerName(KioskSignupState state) {
    final payer = state.payer;
    return '${payer.firstName} ${payer.lastName}'.trim();
  }

  /// The fresh-card law, told to the member. Naming the profile is half the
  /// promise — that is the account a later front-desk charge reads from — and
  /// the replacement sentence is why the notice exists at all, since an
  /// existing member may pay here and really does lose the card on file.
  String _savedCardNotice(String payerName) {
    final who = payerName.trim();
    final whose = who.isEmpty ? 'your profile' : '$who\'s profile';
    return 'This card is saved to $whose and used for future payments. It '
        'replaces any card already on file.';
  }
}

/// A tokenization failure, said inline: never a stop, since the member is one
/// correction away from carrying on.
class _CardError extends StatelessWidget {
  final String message;

  const _CardError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: DesignConstants.kioskCaption.copyWith(
        color: DesignConstants.badRed,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
