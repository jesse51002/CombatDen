import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_stage.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_card_chip.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// D7 — the locked wait while the charge is in flight.
///
/// **There is no footer, no Back, no escape, and that absence is the feature.**
/// A member who abandons mid-charge can end up paid with no membership record,
/// so there is deliberately nothing safe to do here but wait. Do not "fix" the
/// missing button. The 5-minute idle guard is suspended for the same reason,
/// and the session's flow count stays HELD — a live Stripe charge is exactly
/// the case the T+11h45 grace window exists for.
///
/// The bar is indeterminate on purpose. A fake percentage that stalls at 90%
/// is worse than an honest shuttle: it invites the member to decide the iPad
/// has frozen, which is precisely the moment they walk off or tap again.
class KioskPayingScreen extends StatelessWidget {
  const KioskPayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) => prev.preview != cur.preview,
      builder: (context, state) {
        return KioskStage(
          center: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingLarge,
            children: [
              // The shipped kiosk in-flight scale, verbatim from
              // `KioskCheckingIn` — the two "we're working on it" screens on
              // this surface must not spin at two different sizes.
              const AppSpinner(),
              Text(
                'Taking your payment',
                style: DesignConstants.kioskDisplay,
                textAlign: TextAlign.center,
              ),
              Text(
                'This can take up to a minute. Please stay here — don\'t tap '
                'again, and don\'t close this.',
                style: DesignConstants.kioskSubtitle.copyWith(
                  color: DesignConstants.text2nd,
                ),
                textAlign: TextAlign.center,
              ),
              _Amount(state: state),
              const _IndeterminateBar(),
              Text(
                'Hang tight — we\'ll show you when it\'s done.',
                style: DesignConstants.kioskCaption.copyWith(
                  color: DesignConstants.text2nd,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// What is being taken, and off which card — the two facts a member wants
/// confirmed while they wait.
class _Amount extends StatelessWidget {
  final KioskSignupState state;

  const _Amount({required this.state});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          formatMinorUnits(
            state.dueTodayMinorUnits,
            currency: state.currency,
          ),
          style: DesignConstants.kioskMetric,
        ),
        KioskCardChip(brand: state.cardBrand, last4: state.cardLast4),
      ],
    );
  }
}

/// The honest shuttle: an indeterminate track at the kiosk's own content bar
/// thickness, capped to a readable measure so it does not run the whole stage.
class _IndeterminateBar extends StatelessWidget {
  const _IndeterminateBar();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: DesignConstants.kioskHomeMeasure,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        child: LinearProgressIndicator(
          minHeight: DesignConstants.kioskProgressBarThickness,
          color: DesignConstants.primaryColor,
          backgroundColor: DesignConstants.line,
        ),
      ),
    );
  }
}
