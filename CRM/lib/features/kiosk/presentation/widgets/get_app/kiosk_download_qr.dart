import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_qr_frame.dart';

/// The REAL, scannable app-download QR (mockup `.dl-qr`): a live `qr_flutter`
/// code encoding [data], framed in the shared [KioskQrFrame] with the brand
/// glyph badged over its centre (`.dl-badge`).
///
/// The modules are pinned to [DesignConstants.kioskQrModule] on
/// [DesignConstants.kioskQrQuietZone] — fixed dark-on-white in BOTH themes,
/// because a scanner needs that polarity and an inverted code fails or stalls
/// on many phones. The centre badge occludes ~4% of the symbol, comfortably
/// inside level-M's 15% recovery budget and clear of the finder/timing
/// patterns, so the code still scans with the glyph on it.
class KioskDownloadQr extends StatelessWidget {
  final String data;

  const KioskDownloadQr({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        KioskQrFrame(
          accent: true,
          radius: DesignConstants.radiusBig,
          padding: DesignConstants.spacingMedium,
          // A tight box around the code: `QrImageView` measures itself with an
          // internal `LayoutBuilder`, which cannot answer an intrinsic query,
          // and the welcome grid sizes its two panels with `IntrinsicHeight`.
          // The tight SizedBox reports the size directly, so the grid never has
          // to ask the QR's layout builder.
          child: SizedBox(
            width: DesignConstants.kioskAppQrSize,
            height: DesignConstants.kioskAppQrSize,
            child: QrImageView(
              data: data,
              version: QrVersions.auto,
              size: DesignConstants.kioskAppQrSize,
              gapless: true,
              backgroundColor: DesignConstants.kioskQrQuietZone,
              padding: const EdgeInsets.all(DesignConstants.spacingMedium),
              errorCorrectionLevel: QrErrorCorrectLevel.M,
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: DesignConstants.kioskQrModule,
              ),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: DesignConstants.kioskQrModule,
              ),
            ),
          ),
        ),
        const _DownloadBadge(),
      ],
    );
  }
}

/// The CombatDen glyph badged over the code's centre, ringed in the fixed
/// quiet-zone white so it reads as a sticker on the code rather than damage.
class _DownloadBadge extends StatelessWidget {
  const _DownloadBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.spacingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.kioskQrQuietZone,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Container(
        width: DesignConstants.spinnerSizeLarge,
        height: DesignConstants.spinnerSizeLarge,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: DesignConstants.primaryGradient,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          boxShadow: DesignConstants.buttonShadow,
        ),
        child: Icon(
          Symbols.adjust_sharp,
          size: DesignConstants.iconSizeSmall,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.onAccent,
        ),
      ),
    );
  }
}
