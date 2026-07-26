import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_top_bar.dart';
import 'package:crm/features/membership_flow/config/membership_flow_scale.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/config/staff_flow_copy.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// The chrome the nested staff dialogs over the start-memberships run share.
///
/// They stay DIALOGS — each is a genuinely separate task with its own commit,
/// not a stage of the run — so they carry no rail and no identity chip. What
/// they do take is the run's own bands: the context [TaskTopBar], one centred
/// head (a title and at most one line answering it), the body, and the pinned
/// three-slot foot. A task opened over the wizard then reads as part of the
/// same surface, and nothing about it suggests progress through the run.
///
/// It mounts the flow's admin scale and staff voice, so everything composed
/// beneath it — the field boxes, the notices, the sign panel — renders at the
/// desk's size in the desk's words. A nested dialog is pushed on the ROOT
/// navigator, so it sits outside the wizard's own theme and must mount its own.
class TaskDialog extends StatelessWidget {
  /// What this dialog is. Also the surface's accessible name.
  final String what;

  /// The record it was opened against, for the context bar.
  final String? who;

  final VoidCallback? onClose;
  final String closeTooltip;

  /// The centred head — the STEP, never a second copy of [what].
  final String title;
  final String? subtitle;

  final Widget body;

  /// The pinned [TaskFoot] (or the shared `DuplicateFooter`). Null on a phase
  /// that offers no way forward but the close X.
  final Widget? foot;

  final double maxWidth;

  /// Workflow mode: a fixed fraction of the viewport, a pinned head and foot,
  /// and a body that scrolls between them. A short single-task dialog stays
  /// false and hugs its content instead.
  final bool expanded;

  /// Hand [body] the height that is LEFT rather than scrolling it, so a panel
  /// inside can fill the fold and scroll against it. Needs [expanded].
  final bool fillBody;

  const TaskDialog({
    super.key,
    required this.what,
    required this.closeTooltip,
    required this.title,
    required this.body,
    this.who,
    this.onClose,
    this.subtitle,
    this.foot,
    this.maxWidth = DesignConstants.dialogMaxWidth,
    this.expanded = false,
    this.fillBody = false,
  });

  @override
  Widget build(BuildContext context) {
    return MembershipFlowTheme(
      scale: const MembershipFlowScale.admin(),
      copy: const StaffFlowCopy(),
      child: AppDialog(
        title: what,
        titleBar: TaskTopBar(
          what: what,
          who: who,
          onClose: onClose,
          closeTooltip: closeTooltip,
        ),
        expanded: expanded,
        maxWidth: maxWidth,
        contentPadding: const EdgeInsets.all(DesignConstants.paddingBig),
        body: _stage(),
        actions: _foot(),
      ),
    );
  }

  /// Head over body, at the run's own head-to-body gap.
  Widget _stage() {
    final head = _Head(title: title, subtitle: subtitle);
    if (!expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingBig,
        children: [head, body],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        head,
        Expanded(
          child: fillBody ? body : SingleChildScrollView(child: body),
        ),
      ],
    );
  }

  /// The expanded surface draws the footer hairline itself; a hugging one has
  /// to carry its own, or the foot floats off the body it answers.
  Widget? _foot() {
    final bar = foot;
    if (bar == null || expanded) return bar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [const Hairline(), bar],
    );
  }
}

/// One title, and at most one line answering it. Both centred, exactly as the
/// run's own steps carry them.
class _Head extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _Head({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final line = subtitle;
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(title, style: scale.display, textAlign: TextAlign.center),
        if (line != null)
          Text(
            line,
            style: scale.subtitle.copyWith(color: DesignConstants.text2nd),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }
}
