import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/member_details/bloc/member_create_bloc.dart';
import 'package:crm/features/member_details/bloc/member_create_event.dart';
import 'package:crm/features/member_details/bloc/member_create_state.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/duplicate_member_match.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/duplicate_footer.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/duplicate_member_panel.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/member_create_form.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/payer_waiver_sign_body.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

enum _Phase { create, duplicate, sign, success, error }

/// What [StartNewMemberDialog] returns: the chosen member plus whether an
/// authorization was just committed. [committedLink] true means the payer
/// detail must be reloaded (a new payee appeared); false is a direct select
/// of an already-authorized member (just add them to the run).
class StartNewMemberResult {
  final String memberId;
  final bool committedLink;

  const StartNewMemberResult(
    this.memberId, {
    required this.committedLink,
  });
}

/// In-run "New member" dialog: create a brand-new member (with duplicate
/// handling), then authorize the wizard's payer to pay for them (the payee is
/// always the just-created member — the roster-pick step is skipped). On the
/// duplicate branch, "use existing" either selects an already-payable member
/// directly or runs the same authorize chain for them.
///
/// Composes the SAME shared pieces as [StartLinkMemberDialog]
/// ([PayerWaiverSignBody] + `LinkParentRequested` + the settle detection);
/// no waiver-render logic is duplicated. Returns the new/selected member id.
class StartNewMemberDialog extends StatefulWidget {
  final String payerMemberId;
  final String payerName;
  final String gymId;

  /// Member ids the payer can already pay for (their authorized payees). Used
  /// on the duplicate branch to decide select-directly vs. authorize-first.
  final Set<String> authorizedIds;

  const StartNewMemberDialog({
    super.key,
    required this.payerMemberId,
    required this.payerName,
    required this.gymId,
    required this.authorizedIds,
  });

  static Future<StartNewMemberResult?> show({
    required BuildContext context,
    required String payerMemberId,
    required String payerName,
    required String gymId,
    required Set<String> authorizedIds,
  }) {
    final detailBloc = context.read<MemberDetailBloc>();
    return showDialog<StartNewMemberResult>(
      context: context,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: detailBloc),
          BlocProvider(
            create: (_) => MemberCreateBloc(
              repository: MemberRepository(apiClient: ApiClient()),
            ),
          ),
        ],
        child: StartNewMemberDialog(
          payerMemberId: payerMemberId,
          payerName: payerName,
          gymId: gymId,
          authorizedIds: authorizedIds,
        ),
      ),
    );
  }

  @override
  State<StartNewMemberDialog> createState() =>
      _StartNewMemberDialogState();
}

class _StartNewMemberDialogState extends State<StartNewMemberDialog> {
  final _formKey = GlobalKey<MemberCreateFormState>();
  final MemberRepository _repository =
      MemberRepository(apiClient: ApiClient());

  _Phase _phase = _Phase.create;

  List<DuplicateMemberMatch> _matches = const [];
  String? _selectedMatchId;

  // Sign phase.
  String? _payeeId;
  String _payeeName = '';
  String _waiverBody = '';
  String? _waiverVersionId;
  bool _fetchingWaiver = false;
  String? _waiverError;
  String _signerName = '';
  bool _consent = false;
  bool _submitting = false;
  int _tokenBefore = 0;

  String? _errorMessage;

  // ----- Create-bloc reactions -----

  void _onCreateState(MemberCreateState state) {
    switch (state) {
      case MemberCreateDuplicate():
        setState(() {
          _matches = state.matches;
          _selectedMatchId =
              state.matches.isNotEmpty ? state.matches.first.memberId : null;
          _phase = _Phase.duplicate;
        });
      case MemberCreated():
        // A freshly created member — always authorize the payer for them.
        _enterSign(state.memberId, _pendingName);
      case MemberCreateFailure():
        setState(() {
          _phase = _Phase.error;
          _errorMessage = state.needsStripeSetup
              ? '${state.message}\n\nFinish payment setup for this gym in '
                  'Settings, then try again.'
              : state.message;
        });
      case MemberCreateIdle():
      case MemberCreateSubmitting():
        break;
    }
  }

  String _pendingName = '';

  void _onCreate() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    final req = form.buildRequest(widget.gymId);
    _pendingName = '${req.firstName} ${req.lastName}';
    context.read<MemberCreateBloc>().add(MemberCreateSubmitted(req));
  }

  // ----- Duplicate branch -----

  void _onUseExisting() {
    final matchId = _selectedMatchId;
    if (matchId == null) return;
    if (widget.authorizedIds.contains(matchId) ||
        matchId == widget.payerMemberId) {
      Navigator.of(context).pop(
        StartNewMemberResult(matchId, committedLink: false),
      );
      return;
    }
    final match =
        _matches.firstWhere((m) => m.memberId == matchId);
    _enterSign(matchId, match.fullName);
  }

  // ----- Sign phase -----

  void _enterSign(String payeeId, String payeeName) {
    setState(() {
      _payeeId = payeeId;
      _payeeName = payeeName;
      _phase = _Phase.sign;
      _fetchingWaiver = true;
      _waiverError = null;
      _waiverVersionId = null;
      _signerName = '';
      _consent = false;
    });
    _fetchWaiver(payeeId);
  }

  Future<void> _fetchWaiver(String payeeId) async {
    try {
      final waiver = await _repository.getAuthorizedPayerWaiver(payeeId);
      if (!mounted) return;
      setState(() {
        _fetchingWaiver = false;
        _waiverVersionId = waiver.versionId;
        _waiverBody = waiver.body;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fetchingWaiver = false;
        _waiverError = "We couldn't load the waiver. Please try again.";
      });
    }
  }

  bool get _canSign =>
      _consent &&
      _signerName.isNotEmpty &&
      _waiverVersionId != null &&
      !_submitting;

  void _confirmSign() {
    final payeeId = _payeeId;
    final versionId = _waiverVersionId;
    if (payeeId == null || versionId == null || !_canSign) return;
    final bloc = context.read<MemberDetailBloc>();
    final s = bloc.state;
    if (s is MemberDetailLoaded) _tokenBefore = s.refreshToken;
    setState(() => _submitting = true);
    bloc.add(LinkParentRequested(
      memberId: payeeId,
      payerMemberId: widget.payerMemberId,
      waiverVersionId: versionId,
      signerName: _signerName,
      consentAcknowledged: true,
    ));
  }

  void _onDetailSettle(MemberDetailState state) {
    if (!_submitting || state is! MemberDetailLoaded) return;
    if (state.refreshToken > _tokenBefore && !state.isMutating) {
      final payeeId = _payeeId;
      setState(() {
        _submitting = false;
        _phase = _Phase.success;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && payeeId != null) {
          Navigator.of(context).pop(
            StartNewMemberResult(payeeId, committedLink: true),
          );
        }
      });
    } else if (state.actionError != null) {
      setState(() {
        _submitting = false;
        _phase = _Phase.error;
        _errorMessage = state.actionError;
      });
    }
  }

  // ----- Build -----

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<MemberCreateBloc, MemberCreateState>(
          listener: (_, state) => _onCreateState(state),
        ),
        BlocListener<MemberDetailBloc, MemberDetailState>(
          listenWhen: (_, s) =>
              _submitting && s is MemberDetailLoaded,
          listener: (_, state) => _onDetailSettle(state),
        ),
      ],
      child: BlocBuilder<MemberCreateBloc, MemberCreateState>(
        builder: (context, createState) {
          final creating = createState is MemberCreateSubmitting;
          return AppDialog(
            title: _title,
            body: _body(),
            actions: _actions(context, creating),
          );
        },
      ),
    );
  }

  String get _title {
    switch (_phase) {
      case _Phase.create:
        return 'New member';
      case _Phase.duplicate:
        return 'Possible duplicate';
      case _Phase.sign:
        return 'Authorize payer';
      case _Phase.success:
        return 'Member added';
      case _Phase.error:
        return 'Something went wrong';
    }
  }

  Widget _body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The create form stays mounted so entered values survive a
        // "back to edit" round-trip from the duplicate step.
        Offstage(
          offstage: _phase != _Phase.create,
          child: MemberCreateForm(key: _formKey),
        ),
        if (_phase == _Phase.duplicate)
          DuplicateMemberPanel(
            matches: _matches,
            selectedMatchId: _selectedMatchId ?? '',
            onSelect: (id) => setState(() => _selectedMatchId = id),
          ),
        if (_phase == _Phase.sign) _signBody(),
        if (_phase == _Phase.success)
          _Terminal(
            icon: Symbols.check_circle_sharp,
            color: DesignConstants.goodGreen,
            message: '${widget.payerName} is now authorized to pay for '
                '$_payeeName.',
          ),
        if (_phase == _Phase.error)
          _Terminal(
            icon: Symbols.error_sharp,
            color: DesignConstants.badRed,
            message: _errorMessage ?? 'An unexpected error occurred.',
          ),
      ],
    );
  }

  Widget _signBody() {
    if (_fetchingWaiver) {
      return const SizedBox(
        height: DesignConstants.dialogProcessingHeight,
        child: Center(child: AppSpinner()),
      );
    }
    if (_waiverError != null) {
      return _Terminal(
        icon: Symbols.error_sharp,
        color: DesignConstants.badRed,
        message: _waiverError!,
      );
    }
    return PayerWaiverSignBody(
      payerName: widget.payerName,
      payeeName: _payeeName,
      gymName: selectedGym.gymName ?? '',
      waiverBody: _waiverBody,
      enabled: !_submitting,
      onChanged: (name, consent) => setState(() {
        _signerName = name;
        _consent = consent;
      }),
    );
  }

  Widget? _actions(BuildContext context, bool creating) {
    switch (_phase) {
      case _Phase.create:
        return AppDialogActions(
          primaryLabel: 'Create member',
          isLoading: creating,
          primaryOnPressed: creating ? null : _onCreate,
          secondaryLabel: 'Cancel',
          secondaryOnPressed: () => Navigator.of(context).pop(),
        );
      case _Phase.duplicate:
        return DuplicateFooter(
          busy: creating,
          onBackToEdit: () {
            context.read<MemberCreateBloc>().add(const MemberCreateReset());
            setState(() => _phase = _Phase.create);
          },
          onCreateAnyway: () => context
              .read<MemberCreateBloc>()
              .add(const MemberCreateAnywayRequested()),
          onUseExisting: _onUseExisting,
        );
      case _Phase.sign:
        return AppDialogActions(
          primaryLabel: 'Authorize payer',
          isLoading: _submitting,
          primaryOnPressed: _canSign ? _confirmSign : null,
          secondaryLabel: 'Back',
          secondaryOnPressed: _submitting
              ? null
              : () {
                  context
                      .read<MemberCreateBloc>()
                      .add(const MemberCreateReset());
                  setState(() => _phase = _Phase.create);
                },
        );
      case _Phase.success:
        return null;
      case _Phase.error:
        return AppDialogActions(
          primaryLabel: 'Close',
          primaryOnPressed: () => Navigator.of(context).pop(),
        );
    }
  }
}

/// A centered icon + message terminal (success / error).
class _Terminal extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;

  const _Terminal({
    required this.icon,
    required this.color,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Icon(
          icon,
          size: DesignConstants.iconSizeBig,
          weight: DesignConstants.iconWeight,
          color: color,
        ),
        Text(
          message,
          style: DesignConstants.p.copyWith(color: DesignConstants.text),
        ),
      ],
    );
  }
}
