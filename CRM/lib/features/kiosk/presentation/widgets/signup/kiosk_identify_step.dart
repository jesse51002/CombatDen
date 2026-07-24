import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_flow_foot.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_match_search.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_form_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_step_scaffold.dart';

/// "Find your name" — an existing member identifying themselves rather than
/// typing a second account into being.
///
/// It drives the ONE debounced, sequence-guarded search the cubit owns, through
/// the shipped [KioskMatchSearch] — the same composition the payer picker and
/// the payee match use. There is no second search anywhere on the kiosk.
///
/// **Privacy holds exactly as it does everywhere else.** The name rows are
/// avatar-free and print the FULL name and nothing else: a shared lobby iPad
/// showing faces beside searchable names is a directory of everyone who trains
/// here, and two members sharing a first name plus an initial must still be
/// tellable apart. The masked email appears only on the confirm card the next
/// step renders.
///
/// A tapped row does NOT seat anybody. It routes to that confirm card, because
/// two members can share a name and a mis-tap here would otherwise put a
/// stranger's account behind the card about to be typed.
class KioskIdentifyStep extends StatelessWidget {
  const KioskIdentifyStep({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return KioskSignupStepScaffold(
      step: KioskSignupStep.identify,
      title: 'Find your name',
      subtitle: 'Type the name you train under. We\'ll use your account '
          'instead of making a second one.',
      // The decision is a row in a list, so the footer carries only the way
      // back — to the fork, which is a safe destination: nothing was typed.
      foot: KioskFlowFoot(onPrimary: null, onBack: cubit.back),
      child: const KioskSignupFormPanel(
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
