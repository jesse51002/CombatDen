import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/constants/waiver_parameters.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/core/utils/waiver_render.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_flow_foot.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_sign_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_step_scaffold.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_waiver_doc_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_waiver_status.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_who_for.dart';
import 'package:crm/features/memberships/presentation/widgets/waiver_markdown_editor.dart';

/// D4 — read the waiver, type your name, sign.
///
/// One waiver at a time, in the order the plan lists them; the subtitle counts
/// them so a member with three to sign is never surprised by the second.
///
/// **The phase machine is `SignWaiverDialog`'s** — loading → form →
/// submitting → stale → error — with one deliberate difference: on this
/// surface an error is an INLINE retry, never a terminal stop. By the time a
/// member reaches this step their member row and Stripe customer already
/// exist, so ending the whole signup over one failed read would orphan them
/// for nothing. The escape is still in the gutter if they want out.
///
/// **Signed stays signed.** A signature is committed the moment it is
/// recorded; walking Back and forward again skips it rather than presenting it
/// twice, and nothing on this screen can un-sign anything.
class KioskWaiverStep extends StatefulWidget {
  const KioskWaiverStep({super.key});

  @override
  State<KioskWaiverStep> createState() => _KioskWaiverStepState();
}

class _KioskWaiverStepState extends State<KioskWaiverStep> {
  final TextEditingController _signerName = TextEditingController();
  QuillController? _controller;
  bool _consent = false;

  @override
  void initState() {
    super.initState();
    // The body may already be loaded when this step is re-entered.
    _rebuildBody(context.read<KioskSignupCubit>().state);
  }

  @override
  void dispose() {
    _signerName.dispose();
    _controller?.dispose();
    super.dispose();
  }

  /// Render the waiver body with the values the backend substitutes at sign
  /// time: the member's name, the gym's name and today's date are filled, and
  /// the signer line tracks what is being typed — starting as a literal blank
  /// so the member can see exactly where their name will land.
  void _rebuildBody(KioskSignupState state) {
    final body = state.waiver?.currentVersion?.body;
    final old = _controller;
    if (body == null) {
      _controller = null;
    } else {
      final typed = _signerName.text.trim();
      _controller = WaiverMarkdownEditor.controllerFromMarkdown(
        renderWaiverPlaceholders(body, {
          kWaiverParamMemberName: _memberName(state),
          kWaiverParamGymName: selectedGym.gymName ?? '',
          kWaiverParamDate: waiverSignDateUtc(),
          kWaiverParamSignerName: typed.isEmpty ? r'\_\_\_' : typed,
        }),
        readOnly: true,
      );
    }
    old?.dispose();
  }

  String _memberName(KioskSignupState state) {
    final person = state.activePerson;
    return '${person.firstName} ${person.lastName}'.trim();
  }

  bool _canSign(KioskSignupState state) =>
      _consent &&
      _signerName.text.trim().isNotEmpty &&
      !state.submitting &&
      state.waiver != null;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return BlocConsumer<KioskSignupCubit, KioskSignupState>(
      listenWhen: (prev, cur) => prev.waiver != cur.waiver,
      listener: (context, state) {
        setState(() {
          _rebuildBody(state);
          // **Every time a body lands, the tick is cleared.** Consent is given
          // to a DOCUMENT, so it can never carry from the waiver just signed
          // to the next one in the queue, nor survive a republished version.
          // The typed legal name does carry — it is the same person's name,
          // and re-typing it per document is friction with no legal meaning.
          if (state.waiver != null) _consent = false;
        });
      },
      builder: (context, state) {
        final controller = _controller;
        return KioskSignupStepScaffold(
          step: KioskSignupStep.waivers,
          title: _title(state),
          subtitle: _subtitle(state),
          // Pinned: a parent signing four documents in a row must never lose
          // track of which child they are binding, and the document scrolls.
          // "WAIVER FOR", not "SIGNING FOR": the panel beside the document
          // already carries the latter for the person being bound, and one
          // screen saying the same two words twice teaches neither.
          identity: state.isGroup
              ? KioskWhoFor(
                  eyebrow: 'WAIVER FOR',
                  name: _memberName(state),
                )
              : null,
          // The document takes the fold; it scrolls inside its own panel.
          fillBody: true,
          foot: KioskFlowFoot(
            primaryLabel: 'Sign and continue',
            onPrimary: _canSign(state)
                ? () => cubit.signWaiver(signerName: _signerName.text)
                : null,
            onBack: state.submitting ? null : cubit.back,
          ),
          child: controller == null
              ? KioskWaiverStatus(
                  loading: state.waiverLoading,
                  failed: state.waiverFailed,
                  onRetry: cubit.retryWaiver,
                )
              : _Body(
                  state: state,
                  controller: controller,
                  memberName: _memberName(state),
                  signerName: _signerName,
                  consent: _consent,
                  onSignerNameChanged: (_) =>
                      setState(() => _rebuildBody(state)),
                  onConsentChanged: (v) => setState(() => _consent = v),
                  onRetry: cubit.retryWaiver,
                ),
        );
      },
    );
  }

  /// Whose signature this screen is collecting. In a group the run is grouped
  /// by PERSON, so the title names them on EVERY turn — the payer's own
  /// included. The payer holding the iPad is signing on behalf of a child half
  /// the time, and one unnamed screen in a run of named ones is exactly where
  /// the wrong person gets bound.
  String _title(KioskSignupState state) {
    if (!state.isGroup) return 'One signature and you\'re in';
    final first = state.activePerson.firstName.trim();
    if (first.isEmpty) return 'One signature and you\'re in';
    return '$first\'s waiver';
  }

  /// "Required for Unlimited · waiver 1 of 2" — the plan that asked for it and
  /// where the member is in the run.
  String _subtitle(KioskSignupState state) {
    final total = state.waiverQueue.length;
    final position = '${state.waiverIndex + 1} of $total';
    final plan = state.selectedPlan?.planName;
    if (plan == null || plan.trim().isEmpty) return 'Waiver $position';
    return 'Required for ${plan.trim()} · waiver $position';
  }
}

/// The document beside the signing panel — the document is the wider half
/// because reading it is the job, and the panel beside it is three controls.
class _Body extends StatelessWidget {
  final KioskSignupState state;
  final QuillController controller;
  final String memberName;
  final TextEditingController signerName;
  final bool consent;
  final ValueChanged<String> onSignerNameChanged;
  final ValueChanged<bool> onConsentChanged;
  final VoidCallback onRetry;

  const _Body({
    required this.state,
    required this.controller,
    required this.memberName,
    required this.signerName,
    required this.consent,
    required this.onSignerNameChanged,
    required this.onConsentChanged,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final waiver = state.waiver!;
    final version = waiver.currentVersionNumber;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (state.waiverStale)
          const KioskWaiverNotice(
            message: 'The gym updated this waiver — please read and sign the '
                'new version.',
          ),
        if (state.waiverFailed)
          KioskWaiverNotice(
            message: 'That didn\'t go through. Please try again.',
            onRetry: onRetry,
          ),
        Expanded(
          // Stretch, so both cards take the fold's full height: the document
          // fills its reading box, and the signing column can scroll inside
          // itself on a short fold rather than pushing the footer away.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingLarge,
            children: [
              Expanded(
                flex: 3,
                child: KioskWaiverDocPanel(
                  title: waiver.name,
                  versionLabel: version == null ? null : 'Version $version',
                  controller: controller,
                ),
              ),
              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  child: KioskSignPanel(
                    memberName: memberName,
                    signerName: signerName,
                    onSignerNameChanged: onSignerNameChanged,
                    consent: consent,
                    onConsentChanged: onConsentChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
