import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_app_line.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_section_head.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// The "Scan with app" half of the kiosk home — a static QR-code visual
/// placeholder (the live check-in nonce is Phase G, so this renders but does
/// nothing) plus the App Store adoption line and a quiet "Get it" affordance
/// that opens the "Get the CombatDen App" modal (UX-5). Mirrors the mockup QR
/// column.
class KioskQrPanel extends StatelessWidget {
  const KioskQrPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingBig,
      children: [
        const KioskSectionHead(
          title: 'Scan with app',
          subtitle: 'Scan QR code with app for instant check in',
        ),
        const _QrPlaceholder(),
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            const KioskAppLine(
              text: 'Get the CombatDen app in the App Store.',
            ),
            AppOutlineButton(
              text: 'Don\'t have the app? Get it',
              borderColor: DesignConstants.line,
              textColor: DesignConstants.text2nd,
              onPressed: () =>
                  context.read<KioskFlowCubit>().openAppModal(),
            ),
          ],
        ),
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
