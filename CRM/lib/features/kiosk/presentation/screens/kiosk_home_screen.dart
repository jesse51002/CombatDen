import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_adopt_strip.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_home_columns.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_name_search.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_qr_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_signup_stub.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_stage.dart';

/// The kiosk idle home: a centered "Check in" title over a horizontal
/// two-column composition — the "Scan with app" QR half and the "Name search"
/// half, split by a vertical "or" seam — then the lower-emphasis "New here?
/// Sign up" entry, and last the full-width [KioskAdoptStrip]. Full-viewport on
/// the iPad, so it fills the kiosk stage's width rather than a narrow dialog
/// measure (mockup `home` screen).
///
/// [KioskHomeColumns] lays the two halves out as shared head / body bands, so
/// the QR and the search field are co-centred while the two headings stay
/// top-aligned — see its doc for why that departs from the mockup.
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
/// sign up); below it, the single thing that is about later. A newcomer with no
/// account is blocked at the kiosk and outranks a nudge nobody is waiting on,
/// so sign-up keeps the higher slot. It is also the only order in which
/// emphasis and urgency both fall monotonically down the screen.
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
              text: 'New here? Sign up',
              onPressed: () => showKioskSignupStub(context),
            ),
          ),
          const KioskAdoptStrip(),
        ],
      ),
    );
  }
}
