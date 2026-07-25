import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_home_columns.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_qr_frame.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_section_head.dart';

/// The "Scan with app" half of the kiosk home, as the two slots the home's
/// band layout places: the section head, and the QR tile that floats in the
/// flexible middle. The QR is a static visual placeholder — the live check-in
/// nonce is Phase G.
///
/// No foot: the adopt strip spans both columns from the home screen instead.
/// Handing head/body to [KioskHomeColumns] rather than stacking them here is
/// what lets the search field land on this QR's exact optical centre.
KioskHomeHalf kioskQrHalf() => const KioskHomeHalf(
      head: KioskSectionHead(
        title: 'Scan with app',
        subtitle: 'Scan QR code with app for instant check in',
      ),
      body: Center(child: _QrPlaceholder()),
    );

/// A framed QR glyph — deliberately inert, but already inside the shared
/// [KioskQrFrame] so Phase G drops a scannable code into a tile that already
/// has the right fixed dark-on-white contrast.
class _QrPlaceholder extends StatelessWidget {
  const _QrPlaceholder();

  @override
  Widget build(BuildContext context) {
    return KioskQrFrame(
      child: SizedBox(
        width: DesignConstants.heroChartHeight,
        height: DesignConstants.heroChartHeight,
        child: FittedBox(
          child: Icon(
            Symbols.qr_code_2_sharp,
            size: DesignConstants.iconSizeBig,
            weight: DesignConstants.iconWeight,
            // Pinned dark ink, never the theme's `text` — see the token doc.
            color: DesignConstants.kioskQrModule,
          ),
        ),
      ),
    );
  }
}
