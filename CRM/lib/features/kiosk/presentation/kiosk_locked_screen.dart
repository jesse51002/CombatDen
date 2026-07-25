import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The fail-closed screen shown when a kiosk session has ended — its runway
/// elapsed, or the tab reopened past the deadline — while the admin session
/// hasn't yet dropped to login. Calm and terminal: it never exposes the admin
/// workspace.
class KioskLockedScreen extends StatelessWidget {
  const KioskLockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignConstants.backgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignConstants.paddingBig),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingLarge,
            children: [
              const _LockedIcon(),
              Column(
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingSmall,
                children: [
                  Text(
                    'Session ended',
                    style: DesignConstants.kioskDisplay,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'Please see the front desk to continue.',
                    style: DesignConstants.kioskSubtitle.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedIcon extends StatelessWidget {
  const _LockedIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.accentSoft,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Symbols.lock_clock_sharp,
        size: DesignConstants.iconSizeBig,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.primaryColor,
      ),
    );
  }
}
