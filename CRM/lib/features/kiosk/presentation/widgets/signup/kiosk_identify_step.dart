import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_match_search.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_step_scaffold.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_foot.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_form_panel.dart';

/// "Find your name" — an existing member identifying themselves rather than
/// typing a second account into being. It drives the ONE debounced,
/// sequence-guarded search the cubit owns, through [KioskMatchSearch].
///
/// A tapped row does NOT seat anybody: it routes to the next step's confirm
/// card, because two members can share a name and a mis-tap here would
/// otherwise put a stranger's account behind the card about to be typed.
class KioskIdentifyStep extends StatelessWidget {
  const KioskIdentifyStep({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return KioskStepScaffold(
      step: KioskSignupStep.identify,
      title: 'Find your name',
      subtitle: 'Type the name you train under. We\'ll use your account '
          'instead of making a second one.',
      // The decision is a row in a list, so the footer carries only the way
      // back — to the fork, a safe destination: nothing was typed.
      foot: FlowFoot(
        onPrimary: null,
        onBack: cubit.back,
        onEscape: cubit.abandon,
      ),
      child: const FlowFormPanel(
        children: [
          KioskMatchSearch(
            forPayer: true,
            hintText: 'Start typing your name',
            // The shipped payer line ("you can keep paying yourself") names a
            // person who does not exist yet: nothing is seated on this screen.
            noMatchMessage: 'No matches yet. Check the spelling, or go back '
                'and sign up as someone new.',
          ),
        ],
      ),
    );
  }
}
