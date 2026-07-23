import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_exit_lock.dart';

/// The persistent kiosk header: gym identity on the left, the discreet
/// staff-exit lock on the right, a hairline beneath — the mockup's
/// `.kiosk-header`. Fixed above the swapping sub-screen body.
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
        const _LogoMark(),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingTiny,
            children: [
              Text(
                gymName,
                style: DesignConstants.h2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Check in',
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text3rd,
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

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DesignConstants.navMenuButtonSize,
      height: DesignConstants.navMenuButtonSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: DesignConstants.primaryGradient,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        boxShadow: DesignConstants.buttonShadow,
      ),
      child: Icon(
        Symbols.adjust_sharp,
        size: DesignConstants.iconSizeLarge,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.onAccent,
      ),
    );
  }
}
