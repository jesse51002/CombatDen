import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_exit_lock.dart';

/// The full-viewport member surface mounted (in place of the admin workspace)
/// while kiosk is active — no `AppShell`, no nav rail, no admin routes.
///
/// TODO(Phase C): replaced by the real kiosk home + check-in + glance + signup
/// surfaces. This is a **deliberately temporary security-shell placeholder** —
/// it only proves the auth-gate swap and the exit-lock sign-out. Do not build
/// the member UI here; that lands in Phase C behind the `impeccable` pass.
class KioskScreen extends StatelessWidget {
  const KioskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignConstants.backgroundColor,
      body: Stack(
        children: [
          const _KioskPlaceholderBody(),
          Positioned(
            top: DesignConstants.paddingSmall,
            right: DesignConstants.paddingSmall,
            child: const KioskExitLock(),
          ),
        ],
      ),
    );
  }
}

class _KioskPlaceholderBody extends StatelessWidget {
  const _KioskPlaceholderBody();

  @override
  Widget build(BuildContext context) {
    final gymName = selectedGym.gymName ?? 'Your gym';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingMedium,
        children: [
          Icon(
            Symbols.point_of_sale_sharp,
            size: DesignConstants.iconSizeBig,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.primaryColor,
          ),
          Text(
            'Kiosk Mode',
            style: DesignConstants.h1,
            textAlign: TextAlign.center,
          ),
          Text(
            gymName,
            style: DesignConstants.pBig.copyWith(
              color: DesignConstants.text2nd,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
