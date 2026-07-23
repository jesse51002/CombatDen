import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_name_search.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_or_seam.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_qr_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_signup_stub.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_stage.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// The kiosk idle home: a centered "Check in" title over a horizontal
/// two-column composition — the "Scan with app" QR half and the "Name search"
/// half, split by a vertical "or" seam — with a lower-emphasis "New here? Sign
/// up" entry below. Full-viewport on the iPad, so it fills the kiosk stage's
/// width rather than a narrow dialog measure (mockup `home` screen).
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
          // The two halves stretch to equal height so the seam rule spans the
          // taller half; IntrinsicHeight gives the unbounded scroll body a
          // height for that stretch to resolve against.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingLarge,
              children: const [
                Expanded(child: KioskQrPanel()),
                KioskOrSeam(),
                Expanded(child: KioskNameSearch()),
              ],
            ),
          ),
          Center(
            child: AppOutlineButton(
              text: 'New here? Sign up',
              onPressed: () => showKioskSignupStub(context),
            ),
          ),
        ],
      ),
    );
  }
}
