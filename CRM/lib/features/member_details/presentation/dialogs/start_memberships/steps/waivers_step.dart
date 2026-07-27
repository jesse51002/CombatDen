import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'package:crm/core/constants/waiver_parameters.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/core/utils/waiver_render.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/shared/wizard_step_foot.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/waivers/waiver_head_facts.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/waivers/waiver_run_entries.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/waivers/waivers_body.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/waivers/waivers_identity.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_actions.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_step_scaffold.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/memberships/presentation/widgets/waiver_markdown_editor.dart';

/// Frame 6 — the waiver run: read the document, type the legal name, sign.
///
/// One (person, waiver) pair at a time, in queue order, with the WHOLE run
/// listed beside it so a parent signing four documents for two children can
/// see what is left and for whom. The step owns the typed name, the consent
/// tick and the rendered body, because all three are local to one signature —
/// and it CLEARS the first two whenever the pair changes. That clear is a
/// legal invariant, not tidiness: a carried-over name would record somebody as
/// having signed a document they never typed their name on.
class WizardWaiversStep extends StatefulWidget {
  final bool showAddMemberGroup;
  final WizardActions actions;

  const WizardWaiversStep({
    super.key,
    required this.showAddMemberGroup,
    required this.actions,
  });

  @override
  State<WizardWaiversStep> createState() => _WizardWaiversStepState();
}

class _WizardWaiversStepState extends State<WizardWaiversStep> {
  final TextEditingController _signerName = TextEditingController();
  QuillController? _controller;
  bool _consent = false;

  /// waiverId → the gym's name for it, learned as each body loads. The queue
  /// itself only carries a name for a server-gated pair, so without this a
  /// document signed a moment ago would go back to being unnamed on the list.
  final Map<String, String> _seenNames = <String, String>{};

  @override
  void initState() {
    super.initState();
    // The body may already be loaded when the step is re-entered.
    _absorb(context.read<MembershipWizardCubit>().state);
  }

  @override
  void dispose() {
    _signerName.dispose();
    _controller?.dispose();
    super.dispose();
  }

  /// A new pair (or a new body for the same one) is on screen: forget the
  /// signature in progress, remember the document's name, re-render.
  void _onPairChanged(MembershipWizardState state) {
    _signerName.clear();
    _consent = false;
    _absorb(state);
  }

  void _absorb(MembershipWizardState state) {
    final waiver = state.waiver;
    final task = state.currentWaiverTask;
    if (waiver != null && task != null) _seenNames[task.waiverId] = waiver.name;
    _rebuildBody(state);
  }

  /// Render the body with the values the backend substitutes at sign time.
  /// The signer line tracks what is typed, starting as a literal blank so
  /// staff see exactly where the name will land.
  void _rebuildBody(MembershipWizardState state) {
    final body = state.waiver?.currentVersion?.body;
    final old = _controller;
    if (body == null) {
      _controller = null;
    } else {
      final typed = _signerName.text.trim();
      _controller = WaiverMarkdownEditor.controllerFromMarkdown(
        renderWaiverPlaceholders(body, {
          kWaiverParamMemberName: state.currentWaiverTask?.memberName ?? '',
          kWaiverParamGymName: selectedGym.gymName ?? '',
          kWaiverParamDate: waiverSignDateUtc(),
          kWaiverParamSignerName: typed.isEmpty ? r'\_\_\_' : typed,
        }),
        readOnly: true,
      );
    }
    old?.dispose();
  }

  bool _canSign(MembershipWizardState state) =>
      _consent &&
      _signerName.text.trim().isNotEmpty &&
      !state.signing &&
      state.waiver != null;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MembershipWizardCubit>();
    return BlocConsumer<MembershipWizardCubit, MembershipWizardState>(
      listenWhen: (prev, next) =>
          prev.waiver != next.waiver ||
          prev.currentWaiverTask?.key != next.currentWaiverTask?.key,
      listener: (context, state) => setState(() => _onPairChanged(state)),
      builder: (context, state) {
        final copy = MembershipFlowTheme.copyOf(context);
        final head = wizardWaiverHead(state);
        final done = state.allWaiversSigned;
        return WizardStepScaffold(
          step: MembershipWizardStep.waivers,
          hasWaivers: state.hasWaivers,
          showAddMemberGroup: widget.showAddMemberGroup,
          title: copy.waiverStepTitle(
            firstName: head.firstName,
            isGroup: head.isGroup,
          ),
          subtitle: done
              ? null
              : copy.waiverStepSubtitle(
                  index: head.index,
                  total: head.total,
                  planName: head.planName,
                  firstName: head.firstName,
                ),
          identity: WizardWaiversIdentity(
            payerName: state.payer.name,
            signingForName: done ? null : head.memberName,
          ),
          // The document takes the fold and scrolls inside its own panel.
          fillBody: true,
          foot: WizardStepFoot(
            note: WizardWaiversCopy.gate,
            onEscape: widget.actions.close,
            onBack: cubit.canGoBack ? cubit.back : null,
            primaryLabel:
                done ? copy.continueAction : WizardWaiversCopy.signAction,
            onPrimary: done
                ? cubit.next
                : _canSign(state)
                    ? () => cubit.signCurrentWaiver(
                          signerName: _signerName.text,
                        )
                    : null,
          ),
          child: WizardWaiversBody(
            stale: state.waiverStale,
            loading: state.waiverLoad.isLoading,
            failed: state.waiverLoad.isFailed,
            onRetry: cubit.retryWaiver,
            controller: _controller,
            waiverName: state.waiver?.name,
            versionNumber: state.waiver?.currentVersionNumber,
            memberName: head.memberName,
            signerName: _signerName,
            onSignerNameChanged: (_) => setState(() => _rebuildBody(state)),
            onConsentChanged: (value) => setState(() => _consent = value),
            consent: _consent,
            entries: wizardWaiverEntries(state, _seenNames),
            done: done,
          ),
        );
      },
    );
  }
}
