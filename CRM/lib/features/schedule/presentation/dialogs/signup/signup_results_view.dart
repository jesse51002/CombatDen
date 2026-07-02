import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/check_in/presentation/widgets/check_in_processing_view.dart';
import 'package:crm/features/schedule/bloc/schedule_bloc.dart';
import 'package:crm/features/schedule/bloc/schedule_state.dart';
import 'package:crm/features/schedule/presentation/dialogs/signup/signup_result_row.dart';

/// The "Reserve members" per-member breakdown, read live off the
/// [ScheduleBloc]: a summary line, then one row per member (reserved /
/// already reserved / failed — e.g. "Class is full"). There is no retry
/// step here (unlike the batch check-in's "needs confirmation" override) —
/// a failed reservation (usually the room filling up) is just reported.
class SignupResultsView extends StatelessWidget {
  final Map<String, String> memberNames;

  const SignupResultsView({super.key, required this.memberNames});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ScheduleBloc, ScheduleState>(
      builder: (context, state) {
        final result = state is ScheduleLoaded ? state.signupResult : null;
        if (result == null) return const CheckInProcessingView();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingLarge,
          children: [
            Text(
              '${result.signedUpCount} of ${result.results.length} '
              'newly reserved.',
              style:
                  DesignConstants.p.copyWith(color: DesignConstants.text2nd),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingMedium,
              children: result.results
                  .map(
                    (r) => SignupResultRow(
                      item: r,
                      memberName: memberNames[r.memberId] ?? 'Member',
                    ),
                  )
                  .toList(),
            ),
          ],
        );
      },
    );
  }
}
