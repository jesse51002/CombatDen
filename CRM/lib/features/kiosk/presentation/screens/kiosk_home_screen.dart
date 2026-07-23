import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_home_columns.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_name_search.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_qr_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_signup_stub.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_stage.dart';

/// The kiosk idle home: a centered "Check in" title over a horizontal
/// two-column composition — the "Scan with app" QR half and the "Name search"
/// half, split by a vertical "or" seam — with a lower-emphasis "New here? Sign
/// up" entry below. Full-viewport on the iPad, so it fills the kiosk stage's
/// width rather than a narrow dialog measure (mockup `home` screen).
///
/// [KioskHomeColumns] lays the two halves out as shared head / body / foot
/// bands, so the QR and the search field are co-centred while the two headings
/// stay top-aligned — see its doc for why that departs from the mockup.
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
        ],
      ),
    );
  }
}
