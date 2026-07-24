import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_card_facts.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_flow_foot.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_secure_strip.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_form_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_step_scaffold.dart';
import 'package:crm/features/member_details/presentation/dialogs/card_field_box.dart';

/// D5 — the card, and the trust screen around it.
///
/// **The field is the shipped [CardFieldBox]** (founder ruling): the app's one
/// bordered Stripe element, a SINGLE combined line carrying number, expiry,
/// CVC and postal code. The mockup draws four separate boxes; the single-line
/// element wins, because introducing a second payment surface on the one
/// screen that handles card data is exactly the kind of duplication that ends
/// up diverging from the reviewed one.
///
/// **Nothing is charged here and no request is made here.** The footer's
/// primary tokenizes against Stripe and hands the resulting `pm_…` to the
/// cubit; the card number never reaches CombatDen at all. A tokenization
/// failure is an INLINE message — a mistyped number is not a reason to end a
/// signup.
///
/// This is the first step whose escape CONFIRMS. A stray tap here destroys
/// sixteen typed digits plus expiry, CVC and postal code — the most tedious
/// thing to re-enter on a kiosk — so the confirmation is worth the extra tap
/// here in a way it is not on the steps before it.
class KioskCardStep extends StatefulWidget {
  const KioskCardStep({super.key});

  @override
  State<KioskCardStep> createState() => _KioskCardStepState();
}

class _KioskCardStepState extends State<KioskCardStep> {
  /// Stripe's own completeness signal — the primary stays inert until the
  /// element says the card is whole, so "Review" can never fire a tokenize
  /// that was always going to fail.
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
          prev.selectedPlan != cur.selectedPlan,
      builder: (context, state) {
        return KioskSignupStepScaffold(
          step: KioskSignupStep.card,
          title: 'Your card',
          subtitle: state.selectedPlan?.planName,
          foot: KioskFlowFoot(
            primaryLabel: 'Review',
            onPrimary: _complete && !_tokenizing ? _review : null,
            onBack: _tokenizing ? null : cubit.back,
            confirmAbandon: true,
          ),
          child: KioskSignupFormPanel(
            children: [
              KioskSecureStrip(gymName: gym),
              CardFieldBox(
                onComplete: (isComplete) {
                  if (isComplete != _complete) {
                    setState(() => _complete = isComplete);
                  }
                },
              ),
              if (_error != null) _CardError(message: _error!),
              KioskCardFacts(hasRecurring: state.cartHasRecurring),
            ],
          ),
        );
      },
    );
  }
}

/// A tokenization failure, said inline and blame-free. It never becomes a
/// stop: the member is one correction away from carrying on.
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
