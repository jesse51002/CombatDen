import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/profile/data/models/billing_retention.dart';

/// Weekday names indexed by `DateTime.weekday` (1 = Mon … 7 = Sun).
const List<String> _kWeekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const String _kNoValue = '—';

/// The two plain facts under the profile's week strip: how many classes the
/// member trained THIS week, and which weekday their last class was. Numbers,
/// not gamification — this is what carries the rank-less profile.
class StreakFacts extends StatelessWidget {
  const StreakFacts({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MemberProfileBloc, MemberProfileState>(
      builder: (context, state) {
        final retention = state.profile?.retention;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: DesignConstants.paddingBig),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Fact(
                  value: retention == null
                      ? _kNoValue
                      : '${retention.currentWeekAttendedWeekdays.length}',
                  label: 'Classes this week',
                ),
              ),
              Expanded(
                child: _Fact(
                  value: lastClassWeekday(retention),
                  label: 'Last class',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The weekday name of [retention]'s last class, or an em dash when the member
/// has never trained (or the backend's timestamp doesn't parse).
String lastClassWeekday(BillingRetention? retention) {
  final raw = retention?.lastClass;
  if (raw == null || raw.isEmpty) return _kNoValue;
  final at = DateTime.tryParse(raw);
  if (at == null) return _kNoValue;
  return _kWeekdayNames[at.weekday - 1];
}

class _Fact extends StatelessWidget {
  const _Fact({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(value, textAlign: TextAlign.center, style: DesignConstants.h2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
      ],
    );
  }
}
