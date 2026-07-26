import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_rail_index.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_stage.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_shell.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_step_scaffold.dart';

/// The kiosk's binding of the shared [FlowStepScaffold] — the per-SURFACE half
/// of the signup chrome, and the only place the lane names either.
///
/// Two things are bound here, and both are the host's by definition:
/// - the SHELL is the full-screen [KioskStage], the same stage the check-in
///   lane's screens sit in;
/// - the RAIL is read straight off `KioskSignupCubit`, so a step never passes
///   its template or its rung by hand and no two steps can disagree about
///   which one is lit.
///
/// The desk's wizard binds the same scaffold to its own dialog body and its
/// own step spine. Nothing about either shell reaches the shared set.
class KioskStepScaffold extends StatelessWidget {
  /// Which step this is — the rail lights the matching rung.
  final KioskSignupStep step;

  final String title;

  /// The one line under the title — it answers the question the member
  /// actually has in front of this screen, and never sells.
  final String? subtitle;

  /// The pinned `FlowWhoFor` strip, on the steps that are ABOUT one person.
  final Widget? identity;

  /// The step's body — usually a `FlowFormPanel`.
  final Widget child;

  /// The pinned `FlowFoot`.
  final Widget foot;

  /// See [FlowShellParts.fillBody].
  final bool fillBody;

  /// See [FlowShellParts.bodyController].
  final ScrollController? bodyController;

  const KioskStepScaffold({
    super.key,
    required this.step,
    required this.title,
    required this.child,
    required this.foot,
    this.subtitle,
    this.identity,
    this.fillBody = false,
    this.bodyController,
  });

  /// The kiosk's shell. A `static` function rather than a closure so every
  /// step hands the scaffold the same object and none can quietly wrap it.
  static Widget _stage(BuildContext context, FlowShellParts parts) {
    return KioskStage(
      header: parts.header,
      footer: parts.footer,
      fillBody: parts.fillBody,
      bodyScrollController: parts.bodyController,
      child: parts.body,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.step != cur.step || prev.isGroup != cur.isGroup,
      builder: (context, state) {
        final group = state.isGroup;
        return FlowStepScaffold(
          railSteps: group ? kKioskGroupSteps : kKioskSoloSteps,
          railIndex: kioskRailIndex(step, isGroup: group),
          title: title,
          subtitle: subtitle,
          identity: identity,
          fillBody: fillBody,
          bodyController: bodyController,
          foot: foot,
          shell: _stage,
          child: child,
        );
      },
    );
  }
}
