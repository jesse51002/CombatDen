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
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/authorize_payer_pane.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_person_copy.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_foot.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_note.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_panel.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_terminal.dart';
import 'package:crm/shared/widgets/hairline.dart';

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
/// Two things carry across every phase. The create form stays MOUNTED, so a
/// duplicate warning mid-form costs nobody a retype; and nothing on it turns
/// red until the primary has been pressed once, because a form that scolds
/// while it is being filled in teaches staff to ignore it.
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
  String? _waiverName;
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

  String get _payerName =>
      _parties?.payerName ?? StartPersonCopy.fallbackPayer;

  String get _payeeName =>
      _parties?.payeeName ?? StartPersonCopy.fallbackPayee;

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
        _waiverName = waiver.name;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fetchingWaiver = false;
        _waiverError = StartPersonCopy.waiverLoadFailed;
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
          return TaskDialog(
            what: StartPersonCopy.createWhat(widget.direction),
            // Disabled only while the authorization is in flight — the one
            // moment leaving would strand a commit nobody has read yet.
            onClose:
                _submitting ? null : () => Navigator.of(context).pop(),
            closeTooltip: StartPersonCopy.closeSemantic,
            title: _title,
            subtitle: _subtitle,
            expanded: true,
            // The signing phase hands its two panels the whole fold; every
            // other phase scrolls.
            fillBody: _phase == _Phase.sign,
            // The form was designed at the entry flow's content measure
            // (three fields to a row); 480 cramps it into unreadable columns.
            maxWidth: DesignConstants.dialogContentMaxWidth,
            body: _body(),
            foot: _foot(context, creating),
          );
        },
      ),
    );
  }

  String get _title {
    switch (_phase) {
      case _Phase.create:
        return StartPersonCopy.createWhat(widget.direction);
      case _Phase.duplicate:
        return StartPersonCopy.duplicateTitle;
      case _Phase.sign:
        return StartPersonCopy.signTitle(_payerName, _payeeName);
      case _Phase.success:
        return _kSuccessTitle;
      case _Phase.error:
        return _kErrorTitle;
    }
  }

  String? get _subtitle {
    switch (_phase) {
      case _Phase.create:
        return StartPersonCopy.createSubtitle(
          direction: widget.direction,
          gymName: selectedGym.gymName ?? '',
          anchorName: widget.anchorName,
        );
      case _Phase.duplicate:
        return StartPersonCopy.duplicateSubtitle(_matches.length);
      case _Phase.sign:
        return StartPersonCopy.signSubtitle;
      case _Phase.success:
      case _Phase.error:
        return null;
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
          child: TaskPanel(
            children: [
              const TaskNote(StartPersonCopy.createFieldsNote),
              MemberCreateForm(key: _formKey),
            ],
          ),
        ),
        if (_phase == _Phase.duplicate)
          TaskPanel(
            children: [
              DuplicateMemberPanel(
                matches: _matches,
                selectedMatchId: _selectedMatchId ?? '',
                onSelect: (id) => setState(() => _selectedMatchId = id),
              ),
              const Hairline(),
              const TaskNote(StartPersonCopy.duplicateConsequences),
            ],
          ),
        if (_phase == _Phase.sign)
          Expanded(
            child: AuthorizePayerPane(
              fetching: _fetchingWaiver,
              error: _waiverError,
              payerName: _payerName,
              payeeName: _payeeName,
              gymName: selectedGym.gymName ?? '',
              waiverBody: _waiverBody,
              waiverName: _waiverName,
              submitting: _submitting,
              onChanged: (name, consent) => setState(() {
                _signerName = name;
                _consent = consent;
              }),
            ),
          ),
        if (_phase == _Phase.success)
          TaskTerminal(
            icon: Symbols.check_circle_sharp,
            color: DesignConstants.goodGreen,
            message: StartPersonCopy.signSuccess(_payerName, _payeeName),
          ),
        if (_phase == _Phase.error)
          TaskTerminal(
            icon: Symbols.error_sharp,
            color: DesignConstants.badRed,
            message: _errorMessage ?? StartPersonCopy.unexpectedError,
          ),
      ],
    );
  }

  Widget? _foot(BuildContext context, bool creating) {
    switch (_phase) {
      case _Phase.create:
        return TaskFoot(
          primaryLabel: StartPersonCopy.createPrimary,
          busy: creating,
          onPrimary: creating ? null : _onCreate,
          secondaryLabel: StartPersonCopy.cancel,
          onSecondary: () => Navigator.of(context).pop(),
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
        return TaskFoot(
          primaryLabel: StartPersonCopy.signPrimary,
          busy: _submitting,
          onPrimary: _canSign ? _confirmSign : null,
          secondaryLabel: StartPersonCopy.back,
          onSecondary: _submitting
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
        return TaskFoot(
          primaryLabel: StartPersonCopy.close,
          onPrimary: () => Navigator.of(context).pop(),
        );
    }
  }
}

const String _kSuccessTitle = 'Member added';
const String _kErrorTitle = 'Something went wrong';
