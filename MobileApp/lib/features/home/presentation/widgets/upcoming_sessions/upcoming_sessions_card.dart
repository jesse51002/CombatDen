import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/mock_upcoming_sessions.dart';
import 'package:mobile_app/features/home/presentation/widgets/upcoming_sessions/upcoming_session_row.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:customization_engine/theme/theme_image.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';

class UpcomingSessionsCard extends StatelessWidget {
  const UpcomingSessionsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      padding: EdgeInsets.symmetric(vertical: DesignConstants.paddingSmall),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text('Your upcoming sessions', style: DesignConstants.h2),
          _SessionList(sessions: mockUpcomingSessions),
          AppPrimaryButton(
            text: 'Book another Session',
            onPressed: () {},
          ),
          const _StreakFooter(weeks: mockStreakWeeks),
        ],
      ),
    );
  }
}

class _StreakFooter extends StatelessWidget {
  const _StreakFooter({required this.weeks});
  final int weeks;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Image(
          image: ThemeImage.image(
            CombatDenSlots.streakIcon,
            fallback: ApiImage.asset('icon_streak.png'),
          ),
          width: 12,
          height: 15,
          fit: BoxFit.contain,
        ),
        Text(
          "You're on a $weeks week streak!",
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
      ],
    );
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList({required this.sessions});
  final List<MockUpcomingSession> sessions;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < sessions.length; i++) {
      children.add(UpcomingSessionRow(session: sessions[i]));
      children.add(
        Container(
          height: DesignConstants.buttonBorder,
          color: DesignConstants.divider,
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

