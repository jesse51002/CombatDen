import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/class_booking/data/class_detail_args.dart';
import 'package:mobile_app/features/home/bloc/home_bloc.dart';
import 'package:mobile_app/features/home/bloc/home_event.dart';
import 'package:mobile_app/features/home/data/models/upcoming_session.dart';
import 'package:mobile_app/shared/widgets/buttons/app_outline_button.dart';

const double _kGutterWidth = 70;

/// One open reservation in the upcoming-sessions card. "view" opens the class
/// detail (a booked occurrence) when the reservation falls inside the loaded
/// board window; the board refetches on return.
class UpcomingSessionRow extends StatelessWidget {
  const UpcomingSessionRow({super.key, required this.session});

  final UpcomingSession session;

  void _view(BuildContext context) {
    final occurrence = session.occurrence;
    if (occurrence == null) return;
    final homeBloc = context.read<HomeBloc>();
    Navigator.of(context).pushNamed(
      AppRoutes.classDetail,
      arguments: ClassDetailArgs(occurrence: occurrence, booked: true),
    ).then((_) {
      if (!homeBloc.isClosed) homeBloc.add(const HomeRefreshRequested());
    });
  }

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
                  session.timeLabel,
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
                Text(
                  '${session.className} (${session.durationMinutes} min)',
                  style: DesignConstants.h3,
                ),
                if (session.mentor != null && session.mentor!.isNotEmpty)
                  Text(
                    session.mentor!,
                    style: DesignConstants.p.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
              ],
            ),
          ),
          AppOutlineButton(
            text: 'view',
            onPressed:
                session.occurrence != null ? () => _view(context) : null,
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
