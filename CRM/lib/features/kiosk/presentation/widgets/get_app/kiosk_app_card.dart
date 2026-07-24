import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/kiosk_app_copy.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_app_benefits.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_app_steps.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_download_qr.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_glance_panel.dart';
import 'package:crm/shared/widgets/shrink_to_fit.dart';

/// The "Get the app" popup's star card: the accent-soft nested card carrying
/// the title, the three benefit checks, the real scannable download QR, and
/// the two numbered sign-in steps — the whole onboarding in one centred column.
///
/// It wears the same [KioskGlancePanel] chrome the glance's two panels use,
/// only with the accent-soft fill, so the popup's two nested cards are
/// literally the same component as every other card on the kiosk.
///
/// **The title is white-labelled** (founder ruling): a member downloads THEIR
/// GYM's app, so it reads "Get the {gym} App" and never the platform's name.
/// With no gym name known it degrades to "Get the App" rather than inventing
/// one — see [kioskGetAppTitle]. It is also the modal's only title now: the
/// spanning "Welcome to {gym}" header above it was removed (founder ruling —
/// the gym is already named on the kiosk header and right here).
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
      // The popup must never scroll, so on a fold too short for the full
      // onboarding column the WHOLE card scales down together — title, checks,
      // QR and steps keeping their exact proportions — rather than one of them
      // being singled out. On a normal iPad nothing scales at all.
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
              // A very long gym name wraps once, then clips — the title must
              // not turn into a paragraph on top of the card.
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
