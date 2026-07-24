import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_payer_refusal_copy.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_flow_foot.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_match_search.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_form_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_step_scaffold.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_waiver_status.dart';

/// "Someone else is paying" — pick the EXISTING member who pays for this
/// signup.
///
/// It is the shipped kiosk name-search composition, pointed at the payer seat
/// rather than the roster, and it runs the SAME debounce and sequence guard as
/// every other kiosk search.
///
/// **Every pick goes through the no-attached-card gate**, and a refusal is
/// INLINE — the member picks somebody else, or simply carries on paying
/// themselves. It is never a terminal stop, because nothing about this screen
/// has committed anything.
class KioskPayerPickStep extends StatelessWidget {
  const KioskPayerPickStep({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.payerRefusal != cur.payerRefusal ||
          prev.submitting != cur.submitting,
      builder: (context, state) {
        final refusal = state.payerRefusal;
        return KioskSignupStepScaffold(
          step: KioskSignupStep.payerPick,
          title: 'Who\'s paying?',
          subtitle: 'Find the member paying for this. They enter their card '
              'at the end, and everyone here is added to it.',
          foot: KioskFlowFoot(
            // The decision is a row in the list, so the footer carries only
            // the way back.
            onPrimary: null,
            onBack: state.submitting ? null : cubit.back,
          ),
          child: KioskSignupFormPanel(
            children: [
              if (refusal != null)
                KioskWaiverNotice(message: kioskPayerRefusalCopy(refusal)),
              const KioskMatchSearch(forPayer: true),
            ],
          ),
        );
      },
    );
  }
}
