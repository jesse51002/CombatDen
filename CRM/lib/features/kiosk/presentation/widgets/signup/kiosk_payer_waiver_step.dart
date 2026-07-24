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
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_inline_notice.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_waiver_status.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_who_for.dart';
import 'package:crm/features/memberships/presentation/widgets/waiver_markdown_editor.dart';

/// E3 — the authorized-payer agreement, one per payee.
///
/// **The signer is the PAYER every time.** This is not the payee's liability
/// waiver (that is the next screen); it is the payer putting their name to "I
/// am authorised to pay for this person". Same doc-beside-sign composition as
/// D4 so the member learns the pattern once — what changes is the banner, and
/// the progress line, which counts PEOPLE rather than documents.
///
/// "Sign and continue" is **one call**: `PUT /members/{payee}/link` signs and
/// links together and commits immediately, with no group transaction behind
/// it. A 409 means the gym republished the agreement between the read and the
/// tap, so nothing is recorded against text nobody saw — the body reloads and
/// the payer signs the new one.
class KioskPayerWaiverStep extends StatefulWidget {
  const KioskPayerWaiverStep({super.key});

  @override
  State<KioskPayerWaiverStep> createState() => _KioskPayerWaiverStepState();
}

class _KioskPayerWaiverStepState extends State<KioskPayerWaiverStep> {
  final TextEditingController _signerName = TextEditingController();
  QuillController? _controller;
  bool _consent = false;

  @override
  void initState() {
    super.initState();
    _rebuildBody(context.read<KioskSignupCubit>().state);
  }

  @override
  void dispose() {
    _signerName.dispose();
    _controller?.dispose();
    super.dispose();
  }

  /// Render the agreement with the values the backend substitutes at link
  /// time: the PAYER is `{{member_name}}` (they are the party agreeing), the
  /// payee is `{{payee_name}}`, and the signer line tracks what is typed —
  /// starting as a literal blank so the payer can see where it will land.
  void _rebuildBody(KioskSignupState state) {
    final body = state.payerAuthWaiver?.body;
    final old = _controller;
    if (body == null) {
      _controller = null;
    } else {
      final typed = _signerName.text.trim();
      _controller = WaiverMarkdownEditor.controllerFromMarkdown(
        renderWaiverPlaceholders(body, {
          kWaiverParamMemberName: _name(state.payer),
          kWaiverParamPayeeName: _name(state.activePerson),
          kWaiverParamGymName: selectedGym.gymName ?? '',
          kWaiverParamDate: waiverSignDateUtc(),
          kWaiverParamSignerName: typed.isEmpty ? r'\_\_\_' : typed,
        }),
        readOnly: true,
      );
    }
    old?.dispose();
  }

  String _name(KioskSignupPerson person) =>
      '${person.firstName} ${person.lastName}'.trim();

  bool _canSign(KioskSignupState state) =>
      _consent &&
      _signerName.text.trim().isNotEmpty &&
      !state.submitting &&
      state.payerAuthWaiver != null;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return BlocConsumer<KioskSignupCubit, KioskSignupState>(
      listenWhen: (prev, cur) => prev.payerAuthWaiver != cur.payerAuthWaiver,
      listener: (context, state) {
        setState(() {
          // Every time a new agreement body lands, BOTH the typed legal name
          // and the consent tick are cleared — no exceptions. A signature must
          // be a fresh, deliberate act, so nothing carries from the payee just
          // authorized to the next one, nor survives a republished version.
          // Cleared BEFORE the body is rebuilt so the document re-renders with
          // the blank signer placeholder. Legal invariant, guarded by
          // kiosk_signup_waiver_clear_test.dart.
          if (state.payerAuthWaiver != null) {
            _signerName.clear();
            _consent = false;
          }
          _rebuildBody(state);
        });
      },
      builder: (context, state) {
        final controller = _controller;
        return KioskSignupStepScaffold(
          step: KioskSignupStep.waivers,
          title: 'You\'re paying for ${state.activePerson.firstName}',
          subtitle: _subtitle(state),
          // The same pinned element the liability step wears, naming the
          // payee this agreement is about — this run is always per person, so
          // it is never omitted here.
          identity: KioskWhoFor(
            eyebrow: 'PAYING FOR',
            name: _name(state.activePerson),
          ),
          fillBody: true,
          foot: KioskFlowFoot(
            primaryLabel: 'Sign and continue',
            onPrimary: _canSign(state)
                ? () => cubit.signPayerAuth(signerName: _signerName.text)
                : null,
            onBack: state.submitting ? null : cubit.back,
          ),
          child: controller == null
              ? KioskWaiverStatus(
                  loading: state.payerAuthLoading,
                  failed: state.payerAuthFailed,
                  onRetry: cubit.retryPayerAuth,
                )
              : _Body(
                  state: state,
                  controller: controller,
                  payerName: _name(state.payer),
                  payeeName: _name(state.activePerson),
                  signerName: _signerName,
                  consent: _consent,
                  onSignerNameChanged: (_) =>
                      setState(() => _rebuildBody(state)),
                  onConsentChanged: (v) => setState(() => _consent = v),
                  onRetry: cubit.retryPayerAuth,
                ),
        );
      },
    );
  }

  /// "Person 1 of 2 · Ella, then Theo" — the run counts PEOPLE, because that
  /// is what the iPad is being passed around for.
  String _subtitle(KioskSignupState state) {
    final queue = state.waiverPersonQueue;
    final total = queue.isEmpty ? 1 : queue.length;
    final position = 'Person ${state.waiverPersonIndex + 1} of $total';
    final rest = [
      for (var i = state.waiverPersonIndex; i < queue.length; i++)
        if (queue[i] >= 0 && queue[i] < state.persons.length)
          state.persons[queue[i]].firstName,
    ].where((n) => n.trim().isNotEmpty).toList();
    if (rest.length < 2) return position;
    return '$position · ${rest.first}, then ${rest[1]}';
  }
}

/// The agreement beside the signing panel — the document is the wider half
/// because reading it is the job.
class _Body extends StatelessWidget {
  final KioskSignupState state;
  final QuillController controller;
  final String payerName;
  final String payeeName;
  final TextEditingController signerName;
  final bool consent;
  final ValueChanged<String> onSignerNameChanged;
  final ValueChanged<bool> onConsentChanged;
  final VoidCallback onRetry;

  const _Body({
    required this.state,
    required this.controller,
    required this.payerName,
    required this.payeeName,
    required this.signerName,
    required this.consent,
    required this.onSignerNameChanged,
    required this.onConsentChanged,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (state.payerAuthStale)
          const KioskInlineNotice(
            message: 'The gym updated this agreement — please read and sign '
                'the new version.',
          ),
        if (state.payerAuthFailed)
          KioskInlineNotice(
            message: 'That didn\'t go through. Please try again.',
            onRetry: onRetry,
          ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingLarge,
            children: [
              Expanded(
                flex: 3,
                child: KioskWaiverDocPanel(
                  title: state.payerAuthWaiver?.name ??
                      'Authorized Payer Agreement',
                  controller: controller,
                ),
              ),
              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  child: KioskSignPanel(
                    memberName: payerName,
                    eyebrow: 'YOU ARE SIGNING',
                    bannerNote: 'Authorising yourself to pay for $payeeName.',
                    consentLabel: 'I have read this and agree to pay for '
                        '$payeeName. Typing my name counts as my signature.',
                    consentNote: '$payeeName still signs their own liability '
                        'waiver — that\'s the next step.',
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
