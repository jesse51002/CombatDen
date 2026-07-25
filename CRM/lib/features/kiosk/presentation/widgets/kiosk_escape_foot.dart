import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// The way OUT of an in-progress flow: a hairline band carrying one ghost-tier
/// button exiled to the LEFT gutter, in the same place on every screen that
/// has one. The reach cost is the point — a mis-tap that destroys a flow is
/// worse than a longer reach. There is deliberately NO confirmation step:
/// nothing is typed, written or charged yet.
///
/// [firstName] names the member because the head above ASSERTS who they are;
/// "Back" would leave a member who is not Marcus working out what back means.
///
/// It calls [KioskFlowCubit.goHome], which IS the abandon contract (cancels
/// timers, drops in-flight fetches, ends the session flow the lockout's
/// begin/end balance depends on, wipes the member). Never hand-roll a
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
          // Pulled left by exactly the button's own padding so the CHEVRON
          // lands on the content rail; the tap target keeps its full width.
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
