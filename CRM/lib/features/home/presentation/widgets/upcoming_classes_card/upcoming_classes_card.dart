import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/home/data/upcoming_classes.dart';
import 'package:crm/features/home/data/upcoming_classes_generator.dart';
import 'package:crm/features/home/presentation/widgets/upcoming_classes_card/_class_day_group.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Right-hand panel under the hero: a day-grouped list of upcoming classes,
/// each with a thumbnail and instructor. Driven live by the selected gym (the
/// same [selectedGym] memory the rewards store and phone preview read), so the
/// card shows only that gym's classes.
///
/// The card is **capped at the viewport height** and the day list renders
/// top-down: once it fills the cap it stops, and anything beyond is clipped
/// ("cut off") rather than growing the dashboard unbounded. Tapping any class
/// opens the full Schedule screen, so the clipped rows stay reachable.
class UpcomingClassesCard extends StatelessWidget {
  const UpcomingClassesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingBig,
        children: [
          Text('Upcoming Classes', style: DesignConstants.h1),
          Expanded(
            child: ListenableBuilder(
              listenable: selectedGym,
              builder: (context, _) => _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (selectedGym.videoGymId == null) {
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
    // Lay the day list out at its natural height but clip it to the card's
    // (viewport-capped) bounds, top-aligned, so it cuts off instead of
    // extending. No scroll — the clipped rows live on the Schedule screen.
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: 0,
        maxHeight: double.infinity,
        child: _DayGroups(dayGroups: gymUpcomingClasses(detail.classes)),
      ),
    );
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
            ? const AppSpinner()
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
