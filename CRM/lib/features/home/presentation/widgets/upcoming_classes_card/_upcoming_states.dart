import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/home/bloc/upcoming_classes_bloc.dart';
import 'package:crm/features/home/bloc/upcoming_classes_event.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Loading (null message) / empty / select-gym chrome for the Upcoming
/// Classes card.
class UpcomingClassesMessage extends StatelessWidget {
  final String? message;
  const UpcomingClassesMessage(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(
        child: message == null
            ? const AppSpinner()
            : Text(
                message!,
                style:
                    DesignConstants.p.copyWith(color: DesignConstants.text2nd),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}

/// Error chrome with a retry that re-dispatches the load for [gymId].
class UpcomingClassesErrorBody extends StatelessWidget {
  final String gymId;
  const UpcomingClassesErrorBody({required this.gymId, super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        const ErrorMessage(message: 'Could not load upcoming classes.'),
        TextButton(
          onPressed: () => context
              .read<UpcomingClassesBloc>()
              .add(UpcomingClassesLoadRequested(gymId)),
          child: Text(
            'Retry',
            style: DesignConstants.h3
                .copyWith(color: DesignConstants.primaryColor),
          ),
        ),
      ],
    );
  }
}
