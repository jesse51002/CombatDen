import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/models/class_occurrence.dart';
import 'package:mobile_app/features/qr_checkin/bloc/checkin_pick_class_bloc.dart';
import 'package:mobile_app/features/qr_checkin/bloc/checkin_pick_class_event.dart';
import 'package:mobile_app/features/qr_checkin/bloc/checkin_pick_class_state.dart';
import 'package:mobile_app/features/qr_checkin/data/checkin_confirm_args.dart';
import 'package:mobile_app/features/qr_checkin/presentation/widgets/pick_class/pick_class_empty_view.dart';
import 'package:mobile_app/features/qr_checkin/presentation/widgets/pick_class/pick_class_error_view.dart';
import 'package:mobile_app/features/qr_checkin/presentation/widgets/pick_class/pick_class_header.dart';
import 'package:mobile_app/features/qr_checkin/presentation/widgets/pick_class/pick_class_list.dart';
import 'package:mobile_app/shared/widgets/animation/loading_dots.dart';

/// The pick-class step's content: a header over the per-status body (loading /
/// error / empty / the list of today's classes). Picking a class advances the
/// flow to the confirm step.
class PickClassBody extends StatelessWidget {
  const PickClassBody({super.key});

  void _pick(BuildContext context, ClassOccurrence occurrence) {
    Navigator.of(context).pushReplacementNamed(
      AppRoutes.checkinConfirm,
      arguments: CheckinConfirmArgs.fromOccurrence(occurrence),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        const PickClassHeader(),
        Expanded(
          child: BlocBuilder<CheckinPickClassBloc, CheckinPickClassState>(
            builder: (context, state) => _content(context, state),
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, CheckinPickClassState state) {
    switch (state.status) {
      case CheckinPickClassStatus.initial:
      case CheckinPickClassStatus.loading:
        return const Center(child: LoadingDots());
      case CheckinPickClassStatus.error:
        return PickClassErrorView(
          message: state.errorMessage ?? 'Something went wrong.',
          onRetry: () => context
              .read<CheckinPickClassBloc>()
              .add(const CheckinPickClassLoadRequested()),
        );
      case CheckinPickClassStatus.loaded:
        if (state.occurrences.isEmpty) return const PickClassEmptyView();
        return PickClassList(
          occurrences: state.occurrences,
          onPick: (occ) => _pick(context, occ),
        );
    }
  }
}
