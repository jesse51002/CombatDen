import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_adopt_strip.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_home_columns.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_name_search.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_qr_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_stage.dart';

/// The kiosk idle home: a centred "Check in" title over a two-column
/// composition — the "Scan with app" QR half and the "Name search" half, split
/// by a vertical "or" seam — then the lower-emphasis "Start Trial /
/// Membership" entry, and last the full-width [KioskAdoptStrip]. Full-viewport
/// on the iPad, so it fills the stage rather than a narrow dialog measure.
///
/// The adopt strip SPANS both columns rather than living in the QR half:
/// getting the app is a property of the whole screen, and inside one column
/// only that half had a foot and read heavier however small the strip got
/// (founder ruling). Spanning it leaves neither column with a foot.
///
/// Order — sign-up above, adopt strip LAST (founder ruling). Both are
/// footer-weight, so only one may own the terminal slot; the strip's hairline
/// is the screen's one categorical boundary, with every way to get in RIGHT
/// NOW above it and the single thing that is about later below.
class KioskHomeScreen extends StatelessWidget {
  const KioskHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return KioskStage(
      center: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingBig,
        children: [
          Text(
            'Check in',
            style: DesignConstants.kioskDisplay,
            textAlign: TextAlign.center,
          ),
          KioskHomeColumns(
            left: kioskQrHalf(),
            right: kioskNameSearchHalf(),
          ),
          Center(
            child: KioskOutlineButton(
              text: 'Start Trial / Membership',
              // Gated exactly like `selectMember`: past the lockout this
              // shows the closing screen instead of starting a flow. It does
              // NOT begin the session flow — `KioskSignupCubit` owns that
              // latch.
              onPressed: () => context.read<KioskFlowCubit>().startSignup(),
            ),
          ),
          const KioskAdoptStrip(),
        ],
      ),
    );
  }
}
