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
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/payer_waiver_sign_body.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
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
  /// are excluded by the caller.
  final List<MemberSummary> candidates;

  const StartLinkMemberDialog({
    super.key,
    required this.direction,
    required this.anchorMemberId,
    required this.anchorName,
    required this.candidates,
  });

  static Future<String?> show({
    required BuildContext context,
    required AuthorizeDirection direction,
    required String anchorMemberId,
    required String anchorName,
    required List<MemberSummary> candidates,
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

  MemberSummary? _selected;
  bool _checking = false;
  String? _checkError;

  String? _waiverVersionId;
  String _waiverBody = ''; // raw template body; rendered by the sign body
  String _signerName = '';
  bool _consent = false;
  bool _submitting = false;

  /// Snapshot of the bloc's refreshToken before dispatching,
  /// so we can detect a successful commit.
  int _tokenBefore = 0;

  /// The resolved (payer, payee) pair for the currently-picked member — null
  /// until one is picked.
  AuthorizeParties? get _parties {
    final other = _selected;
    if (other == null) return null;
    return resolveAuthorizeParties(
      direction: widget.direction,
      anchorId: widget.anchorMemberId,
      anchorName: widget.anchorName,
      otherId: other.memberId,
      otherName: other.fullName,
    );
  }

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

  /// Select step → fetch the payee's gym default waiver and advance
  /// to the sign step. No eligibility check — adding is unconditional;
  /// the signed waiver is the only gate.
  Future<void> _continueToSign() async {
    final parties = _parties;
    if (parties == null || _checking) return;
    setState(() {
      _checking = true;
      _checkError = null;
    });
    try {
      final waiver = await _repository.getAuthorizedPayerWaiver(
        parties.payeeId,
      );
      if (!mounted) return;
      setState(() {
        _checking = false;
        _waiverVersionId = waiver.versionId;
        _waiverBody = waiver.body;
        _step = _LinkStep.sign;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _checkError = "We couldn't load the waiver. "
            'Please try again.';
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
          final pickedId = _selected?.memberId;
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
        final isSign = _step == _LinkStep.sign;
        return AppDialog(
          title: _title,
          body: isSign
              ? _signBody()
              : _step == _LinkStep.select
                  ? _selectBody()
                  : _terminalBody(state),
          actions: _actions(context, state),
        );
      },
    );
  }

  String get _title {
    switch (_step) {
      case _LinkStep.sign:
        return 'Sign authorized-payer waiver';
      case _LinkStep.success:
        return 'Payer authorized';
      case _LinkStep.error:
        return 'Authorization failed';
      case _LinkStep.select:
        return widget.direction == AuthorizeDirection.addPayee
            ? 'Add someone ${widget.anchorName} pays for'
            : 'Add a payer for ${widget.anchorName}';
    }
  }

  String get _selectIntro {
    if (widget.direction == AuthorizeDirection.addPayee) {
      return "The picked member joins ${widget.anchorName}'s paying "
          'account, so they can be enrolled in this run. The '
          'payer signs their waiver next.';
    }
    return 'The picked member becomes an authorized payer for '
        "${widget.anchorName} and signs ${widget.anchorName}'s "
        'waiver next.';
  }

  Widget _selectBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          _selectIntro,
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text,
          ),
        ),
        SizedBox(
          height: DesignConstants.dialogMemberPickerHeight,
          child: PaginatedMemberPicker(
            fetchPage: _fetchPage,
            pageSize: _pageSize,
            selectedId: _selected?.memberId,
            expand: true,
            onSelected: (entry) {
              final match = widget.candidates.where(
                (m) => m.memberId == entry.id,
              );
              setState(() {
                _selected = match.isEmpty ? null : match.first;
                _checkError = null;
              });
            },
          ),
        ),
        if (_checkError != null)
          Text(
            _checkError!,
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.badRed,
            ),
          ),
      ],
    );
  }

  Widget _signBody() {
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

  Widget _terminalBody(MemberDetailState state) {
    if (_step == _LinkStep.success) {
      final parties = _parties;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Icon(
            Symbols.check_circle_sharp,
            size: DesignConstants.iconSizeBig,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.goodGreen,
          ),
          Text(
            '${parties?.payerName ?? 'The payer'} is now authorized '
            'to pay for ${parties?.payeeName ?? 'this member'}.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text,
            ),
          ),
        ],
      );
    }
    final msg = state is MemberDetailLoaded
        ? (state.actionError ?? 'An unexpected error occurred.')
        : 'An unexpected error occurred.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Icon(
          Symbols.error_sharp,
          size: DesignConstants.iconSizeBig,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.badRed,
        ),
        Text(
          msg,
          style: DesignConstants.p.copyWith(
            color: DesignConstants.badRed,
          ),
        ),
      ],
    );
  }

  Widget? _actions(
    BuildContext context,
    MemberDetailState state,
  ) {
    switch (_step) {
      case _LinkStep.select:
        return AppDialogActions(
          primaryLabel: 'Continue',
          isLoading: _checking,
          primaryOnPressed: _selected == null || _checking
              ? null
              : _continueToSign,
          secondaryLabel: 'Cancel',
          secondaryOnPressed: () =>
              Navigator.of(context).pop(),
        );
      case _LinkStep.sign:
        return AppDialogActions(
          primaryLabel: 'Authorize payer',
          isLoading: _submitting,
          primaryOnPressed: _canSign ? _confirmSign : null,
          secondaryLabel: 'Back',
          secondaryOnPressed: _submitting
              ? null
              : () => setState(() => _step = _LinkStep.select),
        );
      case _LinkStep.success:
      case _LinkStep.error:
        return AppDialogActions(
          primaryLabel: 'Close',
          primaryOnPressed: () => Navigator.of(context).pop(),
        );
    }
  }
}
