import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/state/selected_gym.dart';
import 'package:app_management/features/home/data/upcoming_classes.dart';
import 'package:app_management/features/home/data/upcoming_classes_generator.dart';
import 'package:app_management/features/home/presentation/widgets/upcoming_classes_card/_class_day_group.dart';

/// Right-hand panel under the hero: a day-grouped list of upcoming classes,
/// each with a thumbnail and instructor. Driven live by the selected gym (the
/// same [selectedGym] memory the rewards store and phone preview read), so the
/// card shows only that gym's classes.
class UpcomingClassesCard extends StatelessWidget {
  const UpcomingClassesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingBig,
      children: [
        Text('Upcoming Classes', style: DesignConstants.h1),
        ListenableBuilder(
          listenable: selectedGym,
          builder: (context, _) => _body(),
        ),
      ],
    );
  }

  Widget _body() {
    if (selectedGym.gymId == null) {
      return const _UpcomingMessage('Select a gym to load its classes.');
    }
    final detail = selectedGym.detail;
    if (detail == null) {
      return _UpcomingMessage(
        selectedGym.error != null
            ? 'Could not reach the video service to load this gym\'s classes.'
            : null,
      );
    }
    if (detail.classes.isEmpty) {
      return const _UpcomingMessage('This gym has no classes yet.');
    }
    return _DayGroups(dayGroups: gymUpcomingClasses(detail.classes));
  }
}

class _DayGroups extends StatelessWidget {
  final List<ScheduledClassDayGroup> dayGroups;
  const _DayGroups({required this.dayGroups});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        for (final g in dayGroups) ClassDayGroup(group: g),
      ],
    );
  }
}

/// Loading (null message) / error / empty chrome for the card.
class _UpcomingMessage extends StatelessWidget {
  final String? message;
  const _UpcomingMessage(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
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
