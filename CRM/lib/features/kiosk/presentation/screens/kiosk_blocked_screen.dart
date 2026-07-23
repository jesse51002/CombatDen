import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_blocked_copy.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_stage.dart';

/// The blame-free front-desk handoff shown when the kiosk gate rejects a
/// check-in (or the call fails). It ALWAYS names a plain-language reason so the
/// member isn't confused, then routes them to the desk. Mirrors the mockup
/// blocked screen.
///
/// The reason line comes from `kioskBlockedCopy` — a gate rejection keys off
/// `skip_reason`, a failed call off the backend's stable
/// `CheckInErrorCode`, never off the `detail` prose.
class KioskBlockedScreen extends StatelessWidget {
  const KioskBlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskFlowCubit, KioskFlowState>(
      buildWhen: (prev, cur) =>
          prev.blockedReason != cur.blockedReason ||
          prev.checkInFailed != cur.checkInFailed ||
          prev.checkInErrorCode != cur.checkInErrorCode,
      builder: (context, state) {
        return KioskStage(
          center: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingLarge,
            children: [
              const _BlockedIcon(),
              Text(
                'Let\'s sort this at the front desk',
                style: DesignConstants.kioskDisplay,
                textAlign: TextAlign.center,
              ),
              _WhyBox(
                reason: kioskBlockedCopy(
                  reason: state.blockedReason,
                  failed: state.checkInFailed,
                  code: state.checkInErrorCode,
                ),
              ),
              Text(
                'Nothing\'s wrong. The coach at the desk can sort it and '
                'check you in from there.',
                style: DesignConstants.pBig.copyWith(
                  color: DesignConstants.text2nd,
                ),
                textAlign: TextAlign.center,
              ),
              KioskPrimaryButton(
                text: 'Okay, got it',
                onPressed: () => context.read<KioskFlowCubit>().goHome(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BlockedIcon extends StatelessWidget {
  const _BlockedIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.yellowDark,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
      ),
      child: Icon(
        Symbols.support_agent_sharp,
        size: DesignConstants.iconSizeBig,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.okYellow,
      ),
    );
  }
}

class _WhyBox extends StatelessWidget {
  final String reason;

  const _WhyBox({required this.reason});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: DesignConstants.dialogMaxWidth,
      ),
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        border: Border.all(color: DesignConstants.line),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Text(
            'WHY',
            style: DesignConstants.monoFont.copyWith(
              fontSize: DesignConstants.pSmall.fontSize,
              fontWeight: FontWeight.w600,
              color: DesignConstants.text3rd,
            ),
          ),
          Text(reason, style: DesignConstants.h1Regular),
        ],
      ),
    );
  }
}
