import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/mock_upcoming_sessions.dart';
import 'package:mobile_app/shared/widgets/buttons/app_outline_button.dart';

const double _kGutterWidth = 70;

class UpcomingSessionRow extends StatelessWidget {
  const UpcomingSessionRow({super.key, required this.session});

  final MockUpcomingSession session;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
        vertical: DesignConstants.spacingMedium,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingLarge,
        children: [
          SizedBox(
            width: _kGutterWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingMedium,
              children: [
                Text(session.dayLabel, style: DesignConstants.p),
                Text(
                  session.time,
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingMedium,
              children: [
                Text(session.className, style: DesignConstants.h3),
                Text(
                  session.mentor,
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
          AppOutlineButton(
            text: 'view',
            onPressed: () {},
            padding: EdgeInsets.symmetric(
              horizontal: DesignConstants.paddingSmall,
              vertical: DesignConstants.spacingSmall,
            ),
          ),
        ],
      ),
    );
  }
}
