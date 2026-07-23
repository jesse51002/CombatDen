import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_stage.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// Minimal success confirmation shown after a recorded (or already-recorded)
/// check-in.
///
// TODO(Phase C2): replace this stub with the real retention "glance" screen —
// the streak panel + image-first reward tiles from the mockup. The pieces it
// needs are already carried here on the CheckInResponse in state.checkInResult
// (points_awarded and class_streak_weeks).
class KioskGlanceStubScreen extends StatelessWidget {
  const KioskGlanceStubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskFlowCubit, KioskFlowState>(
      buildWhen: (prev, cur) => prev.checkInResult != cur.checkInResult,
      builder: (context, state) {
        final result = state.checkInResult;
        return KioskStage(
          center: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingLarge,
            children: [
              const _CheckDisc(),
              Text(
                'Checked in',
                style: DesignConstants.big2Bold,
                textAlign: TextAlign.center,
              ),
              if (result != null && result.pointsAwarded > 0)
                Text(
                  '+${result.pointsAwarded} pts',
                  style: DesignConstants.h1.copyWith(
                    color: DesignConstants.primaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              if (result != null && result.classStreakWeeks > 0)
                Text(
                  '${result.classStreakWeeks}-week streak',
                  style: DesignConstants.pBig.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                  textAlign: TextAlign.center,
                ),
              AppPrimaryButton(
                text: 'Done',
                onPressed: () => context.read<KioskFlowCubit>().goHome(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CheckDisc extends StatelessWidget {
  const _CheckDisc();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.goodGreen,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Symbols.check_sharp,
        size: DesignConstants.iconSizeBig,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.onFill(DesignConstants.goodGreen),
      ),
    );
  }
}
