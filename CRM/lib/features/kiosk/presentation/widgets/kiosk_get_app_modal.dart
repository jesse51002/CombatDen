import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_return_timer.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// The app-download page base URL a member's kiosk QR points at. The per-gym
/// download page (`/get-app/<gymId>`) is a separate workstream; the kiosk only
/// points at it. The canonical host/path is still being finalized, so this one
/// named constant is the single switch — never inline the URL at a call site.
const String kKioskAppDownloadBaseUrl = 'https://www.combatden.net/get-app';

/// Build the app-download URL the QR encodes for [gymId].
String kioskAppDownloadUrl(String gymId) => '$kKioskAppDownloadBaseUrl/$gymId';

/// The member-facing "Get the CombatDen App" modal (founder feature UX-5) — a
/// centered overlay funnel opened from a glance tap or the home QR panel. It
/// composes the approved kiosk welcome app-card: a title, the "book / earn /
/// watch" benefit checklist, a REAL scannable download QR (the app-download
/// page for this gym), and the two sign-in steps, closing on its own
/// 60-second auto-return timer + a Done button.
///
/// A veil over the current kiosk view (rendered like the idle warning). The
/// scrim absorbs taps so an accidental touch doesn't dismiss it — only Done or
/// the 60-second timer closes it, both returning to a fresh home. [secondsLeft]
/// is the cubit's modal countdown; [gymId] scopes the QR.
class KioskGetAppModal extends StatelessWidget {
  final String gymId;
  final int secondsLeft;

  const KioskGetAppModal({
    super.key,
    required this.gymId,
    required this.secondsLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        // Opaque so a tap on the veil is swallowed (never leaks to the glance
        // behind it); intentionally does nothing — Done / the 60s timer close.
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: ColoredBox(
          color: DesignConstants.backgroundColor.withValues(alpha: 0.92),
          child: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesignConstants.dialogMaxWidth,
                ),
                child: _AppCard(gymId: gymId, secondsLeft: secondsLeft),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The accent-soft "star" card — the welcome slide's `.app-card` composed with
/// `DesignConstants`: title, benefits, QR, steps, then the timer + Done foot.
class _AppCard extends StatelessWidget {
  final String gymId;
  final int secondsLeft;

  const _AppCard({required this.gymId, required this.secondsLeft});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(DesignConstants.paddingBig),
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      decoration: BoxDecoration(
        color: DesignConstants.accentSoft,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        border: Border.all(
          color: DesignConstants.primaryColor.withValues(alpha: 0.28),
        ),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            'Get the CombatDen App',
            style: DesignConstants.kioskTitle,
            textAlign: TextAlign.center,
          ),
          const _Benefits(),
          _QrFrame(data: kioskAppDownloadUrl(gymId)),
          const _Steps(),
          _Foot(secondsLeft: secondsLeft),
        ],
      ),
    );
  }
}

/// The "book / earn / watch" value props — a centered wrap of checkmark items.
class _Benefits extends StatelessWidget {
  const _Benefits();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      alignment: WrapAlignment.center,
      spacing: DesignConstants.spacingLarge,
      runSpacing: DesignConstants.spacingMedium,
      children: [
        _Benefit(label: 'Book classes'),
        _Benefit(label: 'Earn rewards'),
        _Benefit(label: 'Watch videos'),
      ],
    );
  }
}

class _Benefit extends StatelessWidget {
  final String label;

  const _Benefit({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Icon(
          Symbols.check_sharp,
          size: DesignConstants.iconSizeTiny,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.primaryColor,
        ),
        Text(label, style: DesignConstants.pBig),
      ],
    );
  }
}

/// The framed, real scannable download QR — dark modules on a white quiet zone
/// (high contrast so it scans), lifted in a white tile like the mockup frame.
class _QrFrame extends StatelessWidget {
  final String data;

  const _QrFrame({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.spacingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(
          color: DesignConstants.primaryColor.withValues(alpha: 0.28),
        ),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: QrImageView(
        data: data,
        version: QrVersions.auto,
        size: DesignConstants.kioskAppQrSize,
        gapless: true,
        backgroundColor: DesignConstants.surface,
        padding: const EdgeInsets.all(DesignConstants.spacingMedium),
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        eyeStyle: QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: DesignConstants.text,
        ),
        dataModuleStyle: QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: DesignConstants.text,
        ),
      ),
    );
  }
}

/// The two numbered sign-in steps under the QR.
class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        _Step(number: 1, label: 'Scan to download the app'),
        _Step(number: 2, label: 'Sign in with the email you signed up with'),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String label;

  const _Step({required this.number, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        _StepNumber(number: number),
        Flexible(
          child: Text(
            label,
            style: DesignConstants.pBig,
            textAlign: TextAlign.start,
          ),
        ),
      ],
    );
  }
}

/// A small filled sapphire disc carrying the step number.
class _StepNumber extends StatelessWidget {
  final int number;

  const _StepNumber({required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DesignConstants.iconSizeLarge,
      height: DesignConstants.iconSizeLarge,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$number',
        style: DesignConstants.h3.copyWith(color: DesignConstants.onAccent),
      ),
    );
  }
}

/// The modal's own footer: a hairline, the 60-second auto-close countdown, and
/// a Done button that returns to a fresh home.
class _Foot extends StatelessWidget {
  final int secondsLeft;

  const _Foot({required this.secondsLeft});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        const Hairline(),
        Center(
          child: KioskReturnTimer(
            total: kKioskAppModalTimeout.inSeconds,
            secondsLeft: secondsLeft,
          ),
        ),
        Center(
          child: AppOutlineButton(
            text: 'Done',
            onPressed: () => context.read<KioskFlowCubit>().closeAppModal(),
          ),
        ),
      ],
    );
  }
}
