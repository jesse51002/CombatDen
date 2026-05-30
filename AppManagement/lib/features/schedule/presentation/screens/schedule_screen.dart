import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/core/state/selected_gym.dart';
import 'package:app_management/features/schedule/data/mock_schedule.dart';
import 'package:app_management/features/schedule/data/schedule_generator.dart';
import 'package:app_management/features/schedule/presentation/widgets/header/schedule_header_bar.dart';
import 'package:app_management/features/schedule/presentation/widgets/list/schedule_class_list.dart';
import 'package:app_management/shared/widgets/app_shell.dart';
import 'package:app_management/shared/widgets/section_card.dart';

/// Gym Class Schedule screen.
///
/// Composition (top to bottom):
///   1. "Gym Class Schedule" subtitle
///   2. Header bar — month + chevrons, date-range pill, "Add New Class"
///   3. The week board — built live from the selected gym's classes
class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      activeRoute: AppRoutes.schedule,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignConstants.paddingBig),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingBig,
          children: [
            Text(
              'Gym Class Schedule',
              style: DesignConstants.h1.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
            const ScheduleHeaderBar(
              monthLabel: kScheduleMonthLabel,
              rangeLabel: kScheduleRangeLabel,
            ),
            const _ScheduleBoard(),
          ],
        ),
      ),
    );
  }
}

/// The week board, driven live by the selected gym: only that gym's classes
/// appear, rotated across the week. Loading / error / empty states mirror the
/// rewards store, which reads the same [selectedGym] memory.
class _ScheduleBoard extends StatelessWidget {
  const _ScheduleBoard();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: selectedGym,
      builder: (context, _) {
        if (selectedGym.gymId == null) {
          return const _ScheduleMessage(
            'Select a gym to load its class schedule.',
          );
        }
        final detail = selectedGym.detail;
        if (detail == null) {
          return _ScheduleMessage(
            selectedGym.error != null
                ? 'Could not reach the video service. Start it and reopen '
                      'this screen to load this gym\'s classes.'
                : null,
          );
        }
        if (detail.classes.isEmpty) {
          return const _ScheduleMessage('This gym has no classes yet.');
        }
        return ScheduleClassList(days: gymScheduleDays(detail.classes));
      },
    );
  }
}

/// Loading (null message) / error / empty chrome for the board.
class _ScheduleMessage extends StatelessWidget {
  final String? message;

  const _ScheduleMessage(this.message);

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(
        child: message == null
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: DesignConstants.primaryColor,
                ),
              )
            : Text(
                message!,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}
