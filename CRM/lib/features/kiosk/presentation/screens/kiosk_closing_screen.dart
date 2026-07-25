import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_stage.dart';

/// Shown when a member tries to start a check-in after the session has passed
/// its lockout mark (no new flows). A calm close, never an error — the runway
/// is winding down; the desk can help.
class KioskClosingScreen extends StatelessWidget {
  const KioskClosingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return KioskStage(
      center: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          const _Icon(),
          Text(
            'This kiosk is closing',
            style: DesignConstants.kioskDisplay,
            textAlign: TextAlign.center,
          ),
          Text(
            'Please see the front desk to check in.',
            style: DesignConstants.kioskSubtitle.copyWith(
              color: DesignConstants.text2nd,
            ),
            textAlign: TextAlign.center,
          ),
          KioskOutlineButton(
            text: 'Okay',
            onPressed: () => context.read<KioskFlowCubit>().goHome(),
          ),
        ],
      ),
    );
  }
}

class _Icon extends StatelessWidget {
  const _Icon();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.accentSoft,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Symbols.schedule_sharp,
        size: DesignConstants.iconSizeBig,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.primaryColor,
      ),
    );
  }
}
