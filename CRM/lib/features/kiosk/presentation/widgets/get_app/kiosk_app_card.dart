import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/kiosk_app_copy.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_app_benefits.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_app_steps.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_download_qr.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_glance_panel.dart';
import 'package:crm/shared/widgets/shrink_to_fit.dart';

/// The app pitch's star card — the whole onboarding in one centred column:
/// title, the three benefit checks, the real scannable download QR, and the
/// two numbered sign-in steps, in accent-soft [KioskGlancePanel] chrome.
///
/// **The title is white-labelled** (founder ruling): a member downloads THEIR
/// GYM's app, so it reads "Get the {gym} App", never the platform's name, and
/// degrades to "Get the App" when no gym name is known rather than inventing
/// one (see [kioskGetAppTitle]). It is the surface's ONLY title — the gym is
/// already named on the kiosk header.
class KioskAppCard extends StatelessWidget {
  final String downloadUrl;
  final String? memberEmail;

  /// The gym whose app this is. Null / blank falls back to the generic title.
  final String? gymName;

  const KioskAppCard({
    super.key,
    required this.downloadUrl,
    this.gymName,
    this.memberEmail,
  });

  @override
  Widget build(BuildContext context) {
    return KioskGlancePanel(
      color: DesignConstants.accentSoft,
      borderColor: DesignConstants.primaryColor.withValues(alpha: 0.28),
      // A fold too short for the column scales the WHOLE card down together
      // rather than singling one child out. Nothing scales on a normal iPad.
      child: ShrinkToFit(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingLarge,
          children: [
            Text(
              kioskGetAppTitle(gymName),
              style: DesignConstants.kioskPanelTitle,
              textAlign: TextAlign.center,
              // A very long gym name must not turn the title into a paragraph.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const KioskAppBenefits(),
            KioskDownloadQr(data: downloadUrl),
            KioskAppSteps(memberEmail: memberEmail),
          ],
        ),
      ),
    );
  }
}
