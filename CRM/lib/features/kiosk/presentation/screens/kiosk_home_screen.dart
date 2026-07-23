import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_name_search.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_or_seam.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_qr_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_signup_stub.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_stage.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// The kiosk idle home: the "Check in" title over two stacked, centered
/// halves — scan-with-app (QR placeholder) and name search, joined by an "or"
/// seam — with a lower-emphasis signup entry at the bottom.
class KioskHomeScreen extends StatelessWidget {
  const KioskHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return KioskStage(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: DesignConstants.dialogMaxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingBig,
            children: [
              Text(
                'Check in',
                style: DesignConstants.big2Bold,
                textAlign: TextAlign.center,
              ),
              const KioskQrPanel(),
              const KioskOrSeam(),
              const KioskNameSearch(),
              Center(
                child: AppOutlineButton(
                  text: 'New here? Sign up',
                  onPressed: () => showKioskSignupStub(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
