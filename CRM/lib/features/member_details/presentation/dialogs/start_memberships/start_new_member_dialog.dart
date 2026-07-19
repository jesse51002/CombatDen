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
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/authorize_direction.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/payer_waiver_sign_body.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

enum _Phase { create, duplicate, sign, success, error }

/// What [StartNewMemberDialog] returns: the chosen member plus whether an
/// authorization was just committed. [committedLink] true means the wizard
/// must reload (a new relationship appeared); false is a direct select of an
/// already-related member (just add them to the run/selection).
class StartNewMemberResult {
  final String memberId;
  final bool committedLink;

  const StartNewMemberResult(
    this.memberId, {
    required this.committedLink,
  });
}

/// In-run "New member" dialog: create a brand-new member (with duplicate
/// handling), then authorize the new payer↔payee relationship with the fixed
/// [anchorMemberId]. [direction] decides which side the created/picked person
/// is:
///
/// - [AuthorizeDirection.addPayee] (members step): the anchor is the payer; the
///   new person is a payee the anchor pays for.
/// - [AuthorizeDirection.addPayer] (payer step): the anchor is the payee; the
///   new person is an authorized payer for the anchor.
///
/// The PAYER signs the payee's authorized-payer waiver. On the duplicate
/// branch, "use existing" either selects an already-related member directly or
/// runs the same authorize chain for them.
///
/// Composes the SAME shared pieces as [StartLinkMemberDialog]
/// ([PayerWaiverSignBody] + `LinkParentRequested` + the settle detection);
/// no waiver-render logic is duplicated. Returns the new/selected member id.
class StartNewMemberDialog extends StatefulWidget {
  final AuthorizeDirection direction;

  /// The FIXED party of the authorization (the wizard's payer for
  /// [AuthorizeDirection.addPayee], the launch member for
  /// [AuthorizeDirection.addPayer]).
  final String anchorMemberId;
  final String anchorName;
  final String gymId;

  /// Member ids already in the anchor's relationship on the CREATED side —
  /// used on the duplicate "use existing" branch to decide select-directly vs.
  /// authorize-first (includes the anchor id itself). For
  /// [AuthorizeDirection.addPayee] these are the payer's existing payees; for
  /// [AuthorizeDirection.addPayer] the payee's existing payers.
  final Set<String> relatedIds;

  const StartNewMemberDialog({
    super.key,
    required this.direction,
    required this.anchorMemberId,
    required this.anchorName,
    required this.gymId,
    required this.relatedIds,
  });

  static Future<StartNewMemberResult?> show({
    required BuildContext context,
    required AuthorizeDirection direction,
    required String anchorMemberId,
    required String anchorName,
    required String gymId,
    required Set<String> relatedIds,
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
          direction: direction,
          anchorMemberId: anchorMemberId,
          anchorName: anchorName,
          gymId: gymId,
          relatedIds: relatedIds,
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

  // Sign phase — the created/picked "other" person (their side of the
  // relationship is resolved from [widget.direction]).
  String? _otherId;
  String _otherName = '';
  String _waiverBody = '';
  String? _waiverVersionId;
  bool _fetchingWaiver = false;
  String? _waiverError;
  String _signerName = '';
  bool _consent = false;
  bool _submitting = false;
  int _tokenBefore = 0;

  String? _errorMessage;

  /// The resolved (payer, payee) pair for the created/picked person — null
  /// until [_enterSign] has set the "other" member.
  AuthorizeParties? get _parties {
    final id = _otherId;
    if (id == null) return null;
    return resolveAuthorizeParties(
      direction: widget.direction,
      anchorId: widget.anchorMemberId,
      anchorName: widget.anchorName,
      otherId: id,
      otherName: _otherName,
    );
  }

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
        // A freshly created member — always authorize the relationship.
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
    if (isAlreadyRelated(
      anchorId: widget.anchorMemberId,
      relatedIds: widget.relatedIds,
      memberId: matchId,
    )) {
      // Already on the anchor's relationship — select directly, no new link.
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

  void _enterSign(String otherId, String otherName) {
    final parties = resolveAuthorizeParties(
      direction: widget.direction,
      anchorId: widget.anchorMemberId,
      anchorName: widget.anchorName,
      otherId: otherId,
      otherName: otherName,
    );
    setState(() {
      _otherId = otherId;
      _otherName = otherName;
      _phase = _Phase.sign;
      _fetchingWaiver = true;
      _waiverError = null;
      _waiverVersionId = null;
      _signerName = '';
      _consent = false;
    });
    _fetchWaiver(parties.payeeId);
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
    final parties = _parties;
    final versionId = _waiverVersionId;
    if (parties == null || versionId == null || !_canSign) return;
    final bloc = context.read<MemberDetailBloc>();
    final s = bloc.state;
    if (s is MemberDetailLoaded) _tokenBefore = s.refreshToken;
    setState(() => _submitting = true);
    bloc.add(LinkParentRequested(
      memberId: parties.payeeId,
      payerMemberId: parties.payerId,
      waiverVersionId: versionId,
      signerName: _signerName,
      consentAcknowledged: true,
    ));
  }

  void _onDetailSettle(MemberDetailState state) {
    if (!_submitting || state is! MemberDetailLoaded) return;
    if (state.refreshToken > _tokenBefore && !state.isMutating) {
      final otherId = _otherId;
      setState(() {
        _submitting = false;
        _phase = _Phase.success;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && otherId != null) {
          Navigator.of(context).pop(
            StartNewMemberResult(otherId, committedLink: true),
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
            // The wide surface, hugging its content height: the create form
            // was designed at the entry flow's 760 content measure (three
            // fields to a row), and the width lets the three-button duplicate
            // footer fit — 480 cramped both.
            maxWidth: DesignConstants.dialogMaxWidthWide,
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
    final parties = _parties;
    // Centered at the entry flow's content measure so the form reads
    // identically to AddMemberChrome's create phase; the Center also pins
    // the wide surface to a stable width across phases.
    return Center(
      child: SizedBox(
        width: DesignConstants.dialogContentMaxWidth,
        child: Column(
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
                message: '${parties?.payerName ?? 'The payer'} is now '
                    'authorized to pay for '
                    '${parties?.payeeName ?? 'this member'}.',
              ),
            if (_phase == _Phase.error)
              _Terminal(
                icon: Symbols.error_sharp,
                color: DesignConstants.badRed,
                message: _errorMessage ?? 'An unexpected error occurred.',
              ),
          ],
        ),
      ),
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
    final parties = _parties;
    return PayerWaiverSignBody(
      payerName: parties?.payerName ?? 'The payer',
      payeeName: parties?.payeeName ?? 'this member',
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
