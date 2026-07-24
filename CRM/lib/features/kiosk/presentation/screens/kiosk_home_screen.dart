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

/// The kiosk idle home: a centered "Check in" title over a horizontal
/// two-column composition — the "Scan with app" QR half and the "Name search"
/// half, split by a vertical "or" seam — then the lower-emphasis "Start Trial
/// / Membership" entry, and last the full-width [KioskAdoptStrip].
/// Full-viewport on the iPad, so it fills the kiosk stage's width rather than a
/// narrow dialog measure.
///
/// [KioskHomeColumns] lays the two halves out as shared head / body bands, so
/// the QR and the search field are co-centred while the two headings stay
/// top-aligned — see its doc for why that departs from an earlier design.
///
/// **The adopt strip SPANS both columns instead of sitting inside one.**
/// Getting the app is a property of the whole screen, so it never belonged in
/// the QR half; while it lived there only the left column had a foot and that
/// half read heavier no matter how small the strip got (founder). Spanning it
/// leaves neither column with a foot, and the two balance by construction.
///
/// **Order: sign-up above, adopt strip last.** Both are footer-weight bands, so
/// only one may own the terminal slot. The strip's hairline is the screen's one
/// categorical boundary: above it, every way to get in RIGHT NOW (scan, search,
/// buy); below it, the single thing that is about later. Somebody standing here
/// with nothing to train on is blocked at the kiosk and outranks a nudge nobody
/// is waiting on, so the entry keeps the higher slot. It is also the only order
/// in which emphasis and urgency both fall monotonically down the screen.
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
              // Gated exactly like `selectMember`: past the T+11h45 lockout
              // this shows the calm closing screen instead of starting a
              // flow. It does NOT begin the session flow — `KioskSignupCubit`
              // owns that latch.
              onPressed: () => context.read<KioskFlowCubit>().startSignup(),
            ),
          ),
          const KioskAdoptStrip(),
        ],
      ),
    );
  }
}
