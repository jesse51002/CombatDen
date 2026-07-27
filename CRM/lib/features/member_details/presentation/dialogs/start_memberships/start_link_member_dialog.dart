import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/authorize_direction.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/authorize_payer_pane.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/link_select_panel.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_person_copy.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_foot.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_terminal.dart';
import 'package:crm/shared/widgets/paginated_member_picker.dart';

enum _LinkStep { select, sign, success, error }

/// The wizard's "link someone" jump: pick a gym member to enter one side of a
/// payer↔payee authorization with the fixed [anchorMemberId], then have the
/// PAYER sign the payee's gym default authorized-payer waiver. [direction]
/// decides which side the pick is:
///
/// - [AuthorizeDirection.addPayee] (members step): the anchor is the payer; the
///   pick is a new payee the anchor pays for.
/// - [AuthorizeDirection.addPayer] (payer step): the anchor is the payee; the
///   pick is a new authorized payer for the anchor.
///
/// The roster it searches is already filtered by the caller — anybody the
/// anchor is authorized with is gone from it — so the list SAYS that. A name
/// that can never appear is the one thing a search box cannot explain by
/// itself, and staff otherwise spell it three ways before giving up.
///
/// [preselected] skips the search entirely: the payer switch can offer a
/// person already on the run's roster, and making staff search for a name
/// that is on screen is the annoyance that route exists to end. The
/// authorization itself is unchanged — the same waiver, the same signature,
/// the same commit — which is why it is this dialog opened on its sign step
/// rather than a second authorization path.
///
/// On confirm it dispatches [LinkParentRequested] (`memberId` = payee,
/// `payerMemberId` = payer, who signs) and pops with the PICKED member's id so
/// the wizard refreshes and auto-selects them.
///
/// Shares [PayerWaiverSignBody] + the settle detection with
/// [StartNewMemberDialog]; no waiver-render or commit logic is duplicated.
class StartLinkMemberDialog extends StatefulWidget {
  final AuthorizeDirection direction;

  /// The FIXED party of the authorization (the wizard's payer for
  /// [AuthorizeDirection.addPayee], the launch member for
  /// [AuthorizeDirection.addPayer]).
  final String anchorMemberId;
  final String anchorName;

  /// Roster to choose from; rows already related to the anchor
  /// are excluded by the caller. Unread when [preselected] is given.
  final List<MemberSummary> candidates;

  /// The person the authorization is FOR, when the caller already knows them.
  /// The dialog opens on the sign step for them and never shows the search.
  final MemberPickerEntry? preselected;

  const StartLinkMemberDialog({
    super.key,
    required this.direction,
    required this.anchorMemberId,
    required this.anchorName,
    this.candidates = const [],
    this.preselected,
  });

  static Future<String?> show({
    required BuildContext context,
    required AuthorizeDirection direction,
    required String anchorMemberId,
    required String anchorName,
    List<MemberSummary> candidates = const [],
    MemberPickerEntry? preselected,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: StartLinkMemberDialog(
          direction: direction,
          anchorMemberId: anchorMemberId,
          anchorName: anchorName,
          candidates: candidates,
          preselected: preselected,
        ),
      ),
    );
  }

  @override
  State<StartLinkMemberDialog> createState() =>
      _StartLinkMemberDialogState();
}

class _StartLinkMemberDialogState
    extends State<StartLinkMemberDialog> {
  static const _pageSize = 20;

  final MemberRepository _repository =
      MemberRepository(apiClient: ApiClient());

  _LinkStep _step = _LinkStep.select;

  MemberPickerEntry? _selected;

  /// The select step's Continue is reading the waiver.
  bool _checking = false;

  /// The sign step is reading the waiver — the preselected route only, which
  /// enters the step before the read rather than after it.
  bool _fetching = false;

  /// The waiver read that failed, shown by whichever step is on screen.
  String? _waiverError;

  String? _waiverVersionId;
  String _waiverBody = ''; // raw template body; rendered by the sign body
  String? _waiverName;
  String _signerName = '';
  bool _consent = false;
  bool _submitting = false;

  /// Snapshot of the bloc's refreshToken before dispatching,
  /// so we can detect a successful commit.
  int _tokenBefore = 0;

  @override
  void initState() {
    super.initState();
    final known = widget.preselected;
    if (known == null) return;
    _selected = known;
    _step = _LinkStep.sign;
    _fetching = true;
    unawaited(_openSignStep());
  }

  /// The resolved (payer, payee) pair for the currently-picked member — null
  /// until one is picked.
  AuthorizeParties? get _parties {
    final other = _selected;
    if (other == null) return null;
    return resolveAuthorizeParties(
      direction: widget.direction,
      anchorId: widget.anchorMemberId,
      anchorName: widget.anchorName,
      otherId: other.id,
      otherName: other.name,
    );
  }

  String get _payerName =>
      _parties?.payerName ?? StartPersonCopy.fallbackPayer;

  String get _payeeName =>
      _parties?.payeeName ?? StartPersonCopy.fallbackPayee;

  Future<List<MemberPickerEntry>> _fetchPage(
    String query,
    int startIndex,
  ) async {
    final q = query.toLowerCase();
    final filtered = q.isEmpty
        ? widget.candidates
        : widget.candidates
            .where(
              (m) =>
                  m.fullName.toLowerCase().contains(q),
            )
            .toList();
    if (startIndex >= filtered.length) return const [];
    final end = (startIndex + _pageSize)
        .clamp(0, filtered.length);
    return filtered
        .sublist(startIndex, end)
        .map(
          (m) => MemberPickerEntry(
            id: m.memberId,
            name: m.fullName,
            avatarUrl: m.photoUrl,
          ),
        )
        .toList();
  }

  /// Read the payee's gym default authorized-payer waiver into the sign step.
  /// Both routes in run this ONE read; they differ only in where they wait.
  /// No eligibility check — adding is unconditional; the signed waiver is the
  /// only gate.
  Future<bool> _readWaiver() async {
    final parties = _parties;
    if (parties == null) return false;
    try {
      final waiver = await _repository.getAuthorizedPayerWaiver(
        parties.payeeId,
      );
      if (!mounted) return false;
      setState(() {
        _waiverVersionId = waiver.versionId;
        _waiverBody = waiver.body;
        _waiverName = waiver.name;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Select step → read the waiver, then advance. The step is left only once
  /// the agreement is in hand, so the sign step it lands on is never a
  /// spinner.
  Future<void> _continueToSign() async {
    if (_parties == null || _checking) return;
    setState(() {
      _checking = true;
      _waiverError = null;
    });
    final landed = await _readWaiver();
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (landed) {
        _step = _LinkStep.sign;
      } else {
        _waiverError = StartPersonCopy.waiverLoadFailed;
      }
    });
  }

  /// The preselected route: the sign step is already on screen, so the read
  /// resolves INTO it — its spinner, then its agreement or its failure.
  Future<void> _openSignStep() async {
    final landed = await _readWaiver();
    if (!mounted) return;
    setState(() {
      _fetching = false;
      if (!landed) _waiverError = StartPersonCopy.waiverLoadFailed;
    });
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
    bloc.add(
      LinkParentRequested(
        memberId: parties.payeeId,
        payerMemberId: parties.payerId,
        waiverVersionId: versionId,
        signerName: _signerName,
        consentAcknowledged: true,
      ),
    );
    // Do NOT pop here — BlocConsumer below detects success/failure.
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<MemberDetailBloc, MemberDetailState>(
      listenWhen: (_, s) =>
          _submitting && s is MemberDetailLoaded,
      listener: (context, state) {
        if (state is! MemberDetailLoaded) return;
        if (!_submitting) return;
        if (state.refreshToken > _tokenBefore &&
            !state.isMutating) {
          // Committed — pop with the PICKED member's id so the
          // wizard can add/select them.
          final pickedId = _selected?.id;
          setState(() {
            _submitting = false;
            _step = _LinkStep.success;
          });
          // Pop after a brief frame so the success UI renders.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop(pickedId);
          });
        } else if (state.actionError != null) {
          setState(() {
            _submitting = false;
            _step = _LinkStep.error;
          });
        }
      },
      builder: (context, state) {
        final signing = _step == _LinkStep.sign;
        return TaskDialog(
          what: StartPersonCopy.findWhat,
          onClose: _submitting ? null : () => Navigator.of(context).pop(),
          closeTooltip: StartPersonCopy.closeSemantic,
          title: _title,
          subtitle: _subtitle,
          expanded: true,
          fillBody: signing || _step == _LinkStep.select,
          maxWidth: DesignConstants.dialogContentMaxWidth,
          body: _body(state),
          foot: _foot(context),
        );
      },
    );
  }

  String get _title {
    switch (_step) {
      case _LinkStep.sign:
        return StartPersonCopy.signTitle(_payerName, _payeeName);
      case _LinkStep.success:
        return _kSuccessTitle;
      case _LinkStep.error:
        return _kErrorTitle;
      case _LinkStep.select:
        return StartPersonCopy.findTitle;
    }
  }

  String? get _subtitle {
    switch (_step) {
      case _LinkStep.sign:
        return StartPersonCopy.signSubtitle;
      case _LinkStep.select:
        return StartPersonCopy.findSubtitle(
          direction: widget.direction,
          anchorName: widget.anchorName,
        );
      case _LinkStep.success:
      case _LinkStep.error:
        return null;
    }
  }

  Widget _body(MemberDetailState state) {
    switch (_step) {
      case _LinkStep.select:
        return _selectBody();
      case _LinkStep.sign:
        return AuthorizePayerPane(
          // Both are false on the search route — it reads the waiver BEFORE
          // entering this step. The preselected route enters first, so it is
          // the one that can be seen loading or failing here.
          fetching: _fetching,
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
        );
      case _LinkStep.success:
        return TaskTerminal(
          icon: Symbols.check_circle_sharp,
          color: DesignConstants.goodGreen,
          message: StartPersonCopy.signSuccess(_payerName, _payeeName),
        );
      case _LinkStep.error:
        return TaskTerminal(
          icon: Symbols.error_sharp,
          color: DesignConstants.badRed,
          message: state is MemberDetailLoaded
              ? (state.actionError ?? StartPersonCopy.unexpectedError)
              : StartPersonCopy.unexpectedError,
        );
    }
  }

  Widget _selectBody() {
    return LinkSelectPanel(
      direction: widget.direction,
      anchorName: widget.anchorName,
      fetchPage: _fetchPage,
      pageSize: _pageSize,
      selectedId: _selected?.id,
      error: _waiverError,
      onSelected: (entry) => setState(() {
        _selected = entry;
        _waiverError = null;
      }),
    );
  }

  Widget _foot(BuildContext context) {
    switch (_step) {
      case _LinkStep.select:
        return TaskFoot(
          primaryLabel: StartPersonCopy.findPrimary,
          busy: _checking,
          onPrimary: _selected == null || _checking
              ? null
              : _continueToSign,
          secondaryLabel: StartPersonCopy.cancel,
          onSecondary: () => Navigator.of(context).pop(),
        );
      case _LinkStep.sign:
        return TaskFoot(
          primaryLabel: StartPersonCopy.signPrimary,
          busy: _submitting,
          onPrimary: _canSign ? _confirmSign : null,
          secondaryLabel: StartPersonCopy.back,
          // There is no search to go back TO when the person was handed in,
          // so Back leaves — onto the surface that named them, which is where
          // picking them again (and so re-reading a waiver that failed) is.
          onSecondary: _submitting
              ? null
              : widget.preselected != null
                  ? () => Navigator.of(context).pop()
                  : () => setState(() => _step = _LinkStep.select),
        );
      case _LinkStep.success:
      case _LinkStep.error:
        return TaskFoot(
          primaryLabel: StartPersonCopy.close,
          onPrimary: () => Navigator.of(context).pop(),
        );
    }
  }
}

const String _kSuccessTitle = 'Payer authorized';
const String _kErrorTitle = 'Authorization failed';
