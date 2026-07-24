import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_consent_check.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_field_box.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';

/// The signing half of the waiver step: who this signature is FOR, the typed
/// legal name, and the consent tick.
///
/// **The signature model is a typed legal name plus an explicit consent
/// acknowledgement** — exactly what the backend records and exactly what the
/// desk's own `SignWaiverPanel` collects. There is no drawn signature: it
/// would be a new stored artefact with no backend behind it, and a finger
/// scrawl on a shared iPad is worse evidence than a typed name, not better.
///
/// The "signing for" banner is `SignWaiverDialog`'s, at kiosk scale, and it
/// keeps the guardian clause: a parent signing for a child is the normal case
/// in a gym, and a line that only addresses the member would quietly make them
/// wonder whether they may.
/// The payer-auth variant passes its own [eyebrow] / [bannerNote] /
/// [consentLabel]: the same three controls answer a different question there
/// ("you are signing, authorising yourself to pay for X"), and a panel that
/// still said "SIGNING FOR Ella" while the payer types their own name would be
/// wrong about who is bound.
class KioskSignPanel extends StatelessWidget {
  /// Whose signature this is — the person the waiver binds.
  final String memberName;

  /// The banner's mono eyebrow.
  final String eyebrow;

  /// The quiet line under the name in the banner.
  final String bannerNote;

  /// The consent tick's line, and its own quieter second line.
  final String consentLabel;
  final String consentNote;

  final TextEditingController signerName;
  final ValueChanged<String> onSignerNameChanged;

  final bool consent;
  final ValueChanged<bool> onConsentChanged;

  const KioskSignPanel({
    super.key,
    required this.memberName,
    required this.signerName,
    required this.onSignerNameChanged,
    required this.consent,
    required this.onConsentChanged,
    this.eyebrow = 'SIGNING FOR',
    this.bannerNote =
        'Signed by you, or by a parent / legal guardian on your behalf.',
    this.consentLabel = 'I have read this waiver and agree to it. Typing my '
        'name counts as my signature.',
    this.consentNote = 'Your name appears in the document as you type it. A '
        'copy goes to your email.',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        border: Border.all(color: DesignConstants.line),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          _SigningFor(
            memberName: memberName,
            eyebrow: eyebrow,
            note: bannerNote,
          ),
          KioskFieldBox(
            controller: signerName,
            label: 'Type your full legal name',
            hintText: memberName,
            icon: Symbols.edit_sharp,
            onChanged: onSignerNameChanged,
          ),
          KioskConsentCheck(
            value: consent,
            onChanged: onConsentChanged,
            label: consentLabel,
            note: consentNote,
          ),
        ],
      ),
    );
  }
}

class _SigningFor extends StatelessWidget {
  final String memberName;
  final String eyebrow;
  final String note;

  const _SigningFor({
    required this.memberName,
    required this.eyebrow,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor10,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          InstructorAvatar(
            name: memberName,
            diameter: DesignConstants.iconSizeBig,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingSmall,
              children: [
                Text(eyebrow, style: DesignConstants.kioskEyebrow),
                Text(
                  memberName,
                  style: DesignConstants.kioskName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  note,
                  style: DesignConstants.kioskCaption.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
