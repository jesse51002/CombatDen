import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_app_line.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_section_head.dart';

/// The "Scan with app" half of the kiosk home — a static QR-code visual
/// placeholder (the live check-in nonce is Phase G, so this renders but does
/// nothing) plus the App Store adoption line. Mirrors the mockup QR column.
class KioskQrPanel extends StatelessWidget {
  const KioskQrPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingBig,
      children: const [
        KioskSectionHead(
          title: 'Scan with app',
          subtitle: 'Scan QR code with app for instant check in',
        ),
        _QrPlaceholder(),
        KioskAppLine(text: 'Get the CombatDen app in the App Store.'),
      ],
    );
  }
}

/// A framed, lifted white tile carrying a QR glyph — a placeholder only (the
/// real per-scan code is Phase G). It is deliberately inert.
class _QrPlaceholder extends StatelessWidget {
  const _QrPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DesignConstants.heroChartHeight,
      height: DesignConstants.heroChartHeight,
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        border: Border.all(color: DesignConstants.line),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: FittedBox(
        child: Icon(
          Symbols.qr_code_2_sharp,
          size: DesignConstants.iconSizeBig,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.text,
        ),
      ),
    );
  }
}
