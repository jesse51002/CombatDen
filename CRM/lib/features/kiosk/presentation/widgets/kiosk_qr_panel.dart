import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_app_line.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_home_columns.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_qr_frame.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_section_head.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// The "Scan with app" half of the kiosk home, as the three slots the home's
/// band layout places (mockup `.home-panel`): the section head, the QR tile
/// that floats in the flexible middle (`.qr-wrap`), and the app-adoption block
/// pinned below it behind a hairline (`.qr-adopt`).
///
/// The QR is a static visual placeholder — the live check-in nonce is Phase G,
/// so it renders but does nothing. The adoption block's "Get it" opens the
/// "Get the CombatDen App" modal (UX-5).
///
/// Handing the head/body/foot to [KioskHomeColumns] rather than stacking them
/// here is what lets the search half's field land on this QR's exact optical
/// centre: both bodies share one flexible band, so this footer no longer
/// drags the two columns out of alignment.
KioskHomeHalf kioskQrHalf() => const KioskHomeHalf(
      head: KioskSectionHead(
        title: 'Scan with app',
        subtitle: 'Scan QR code with app for instant check in',
      ),
      body: Center(child: _QrPlaceholder()),
      foot: _AdoptFooter(),
    );

/// A framed QR tile carrying a QR glyph — a placeholder only (the real
/// per-scan code is Phase G). It is deliberately inert, but already sits in
/// the shared [KioskQrFrame] so Phase G drops a scannable code into a tile
/// that already has the right fixed dark-on-white contrast.
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

/// The mockup's `.qr-adopt`: the app-adoption block that closes the QR half,
/// separated from the flexible QR band by a hairline so it reads as the
/// column's footer rather than content floating below the code.
class _AdoptFooter extends StatelessWidget {
  const _AdoptFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        const Hairline(),
        const Center(
          child: KioskAppLine(
            text: 'Get the CombatDen app in the App Store.',
          ),
        ),
        Center(
          child: KioskPrimaryButton(
            text: 'Don\'t have the app? Get it',
            onPressed: () => context.read<KioskFlowCubit>().openAppModal(),
          ),
        ),
      ],
    );
  }
}
