import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_name_format.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_class_grid.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_stage.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// The chosen member's today-classes screen: a greeting head over the grid of
/// classes open for check-in right now. Mirrors the mockup class-pick screen.
class KioskClassPickScreen extends StatelessWidget {
  const KioskClassPickScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskFlowCubit, KioskFlowState>(
      buildWhen: (prev, cur) =>
          prev.selectedMember != cur.selectedMember ||
          prev.classesLoading != cur.classesLoading ||
          prev.classes != cur.classes ||
          prev.classesFailed != cur.classesFailed,
      builder: (context, state) {
        final name = kioskFirstName(state.selectedMember?.name);
        return KioskStage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingBig,
            children: [
              _Head(name: name),
              _Content(state: state),
            ],
          ),
        );
      },
    );
  }
}

class _Head extends StatelessWidget {
  final String name;

  const _Head({required this.name});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text('Hi $name, pick your class', style: DesignConstants.kioskDisplay),
        Text(
          'Open for check-in right now · tap a class to check in',
          style: DesignConstants.pBig.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}

class _Content extends StatelessWidget {
  final KioskFlowState state;

  const _Content({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.classesLoading) {
      return const Padding(
        padding: EdgeInsets.all(DesignConstants.paddingBig),
        child: Center(child: AppSpinner()),
      );
    }
    if (state.classesFailed) {
      return const _Note(
        'We couldn\'t load classes right now — please see the front desk.',
      );
    }
    if (state.classes.isEmpty) {
      return const _Note(
        'No classes are open for check-in right now — please see the '
        'front desk.',
      );
    }
    return KioskClassGrid(classes: state.classes);
  }
}

class _Note extends StatelessWidget {
  final String message;

  const _Note(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(
        child: Text(
          message,
          style: DesignConstants.h3Regular.copyWith(
            color: DesignConstants.text2nd,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
