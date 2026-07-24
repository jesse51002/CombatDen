import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// The way OUT of an in-progress flow (mockup `.escape-foot`): a hairline band
/// closing the screen, carrying a single ghost-tier button exiled to the LEFT
/// gutter — far from the primary action and far from the tappable content, in
/// the same place on every screen that has one. The reach cost is the point:
/// this is an escape hatch, and a mis-tap that destroys a flow is worse than a
/// slightly longer reach. It deliberately mirrors `KioskGlanceFoot` — the
/// kiosk's one rule is "the way out is along the bottom hairline".
///
/// [firstName] names the member because the head one line above ASSERTS who
/// they are ("Hi Marcus, pick your class"); the escape has to answer that
/// assertion, so it names the person rather than the navigation. A member who
/// is not Marcus reads their own situation in the button, where "Back" would
/// make them work out what "back" means.
///
/// There is NO confirmation step: nothing has been typed, nothing written, no
/// charge exists — and the member is already flustered from mis-tapping once,
/// so a confirm dialog would be a second trap.
///
/// It calls [KioskFlowCubit.goHome], which already IS the abandon contract:
/// it cancels the flow's timers, bumps the search/class/glance sequence
/// counters so in-flight fetches are dropped, ends the session flow (the
/// begin/end balance the T+11h45 lockout depends on), and emits a fresh home
/// with the member — name, search query, results — wiped. Never hand-roll a
/// navigation that skips it.
class KioskEscapeFoot extends StatelessWidget {
  final String firstName;

  const KioskEscapeFoot({super.key, required this.firstName});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        const Hairline(),
        Align(
          alignment: Alignment.centerLeft,
          // Pulled left by exactly the button's own horizontal padding, so the
          // CHEVRON lands on the screen's content rail (flush with the head
          // and the first card) instead of sitting a pad-width inside it. The
          // tap target keeps its full padded width; only the optical edge
          // moves.
          child: Transform.translate(
            offset: Offset(-DesignConstants.kioskButtonGhostPadding.left, 0),
            child: KioskGhostButton(
              text: 'Not $firstName?',
              onPressed: () => context.read<KioskFlowCubit>().goHome(),
            ),
          ),
        ),
      ],
    );
  }
}
