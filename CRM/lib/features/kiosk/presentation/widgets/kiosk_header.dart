import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_exit_lock.dart';
import 'package:crm/shared/widgets/navigation/gym_logo.dart';

/// The persistent kiosk header: gym identity on the left, the discreet
/// staff-exit lock on the right, a hairline beneath. Fixed above the
/// swapping sub-screen body.
class KioskHeader extends StatelessWidget {
  const KioskHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: DesignConstants.lineSoft),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingBig,
          vertical: DesignConstants.paddingSmall,
        ),
        child: Row(
          children: [
            const Expanded(child: _Identity()),
            const KioskExitLock(),
          ],
        ),
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity();

  @override
  Widget build(BuildContext context) {
    final gymName = selectedGym.gymName ?? 'Your gym';
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        // The gym's uploaded logo when it has one, else the CombatDen mark —
        // the same real-gym-identity treatment the admin nav chrome uses.
        const GymLogo(size: DesignConstants.navMenuButtonSize),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingTiny,
            children: [
              Text(
                gymName,
                style: DesignConstants.kioskName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Check in',
                style: DesignConstants.kioskTag.copyWith(
                  color: DesignConstants.text2nd,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
