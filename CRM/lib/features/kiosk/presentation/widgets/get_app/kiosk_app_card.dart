import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_app_benefits.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_app_steps.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_download_qr.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_glance_panel.dart';

/// The welcome screen's star panel (mockup `.app-card`): the accent-soft card
/// carrying the title, the three benefit checks, the real scannable download
/// QR, and the two numbered sign-in steps — the whole onboarding in one
/// column, centred in the panel.
///
/// This card's own title is the modal's title: the mockup's screen sits AFTER
/// a signup and opens on a personalised `Welcome to {gym}, {name}!`, but the
/// modal also opens from the idle home where no member is known, so that
/// greeting is omitted rather than faked.
class KioskAppCard extends StatelessWidget {
  final String downloadUrl;
  final String? memberEmail;

  const KioskAppCard({
    super.key,
    required this.downloadUrl,
    this.memberEmail,
  });

  @override
  Widget build(BuildContext context) {
    return KioskGlancePanel(
      color: DesignConstants.accentSoft,
      borderColor: DesignConstants.primaryColor.withValues(alpha: 0.28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            'Get the CombatDen App',
            style: DesignConstants.h1,
            textAlign: TextAlign.center,
          ),
          const KioskAppBenefits(),
          KioskDownloadQr(data: downloadUrl),
          KioskAppSteps(memberEmail: memberEmail),
        ],
      ),
    );
  }
}
