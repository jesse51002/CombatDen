import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/constants/waiver_parameters.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/core/utils/waiver_render.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/memberships/presentation/widgets/waiver_markdown_editor.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/paginated_member_picker.dart';
import 'package:crm/shared/widgets/sign_waiver_panel.dart';

enum _LinkStep { select, sign, success, error }

/// Authorizes a payer for a member in two steps: (1) pick the payer
/// and run the backend eligibility check (`/link/check`), then
/// (2) show the gym's default authorized-payer waiver for the payer
/// to sign (typed name + consent). On confirm it dispatches
/// [LinkParentRequested] — the payee is [subjectMemberId], the
/// chosen account is the payer and the waiver signer, and the
/// backend records the signature + the authorization atomically.
///
/// The picker is fed from the already-loaded roster ([candidates]);
/// the check + waiver fetch go through a repository built on the
/// shared [ApiClient].
class LinkParentDialog extends StatefulWidget {
  /// The member being paid for (the payee / link path member).
  final String subjectMemberId;

  /// The payee's display name, for the sign-step copy.
  final String subjectName;

  /// Roster to choose a payer from, minus the subject themselves.
  final List<MemberSummary> candidates;

  const LinkParentDialog({
    super.key,
    required this.subjectMemberId,
    required this.subjectName,
    required this.candidates,
  });

  static Future<void> show({
    required BuildContext context,
    required String subjectMemberId,
    required String subjectName,
    required List<MemberSummary> candidates,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: LinkParentDialog(
          subjectMemberId: subjectMemberId,
          subjectName: subjectName,
          candidates: candidates,
        ),
      ),
    );
  }

  @override
  State<LinkParentDialog> createState() =>
      _LinkParentDialogState();
}

class _LinkParentDialogState extends State<LinkParentDialog> {
  static const _pageSize = 20;

  final MemberRepository _repository =
      MemberRepository(apiClient: ApiClient());

  _LinkStep _step = _LinkStep.select;

  // ── Select step ──────────────────────────────────────────
  MemberSummary? _selected;
  bool _checking = false;
  String? _checkError;

  // ── Sign step ────────────────────────────────────────────
  QuillController? _waiverController;
  String? _waiverVersionId;
  String _waiverBody = ''; // raw template body; rendered into the controller
  String _signerName = '';
  bool _consent = false;
  bool _submitting = false;

  /// Snapshot of the bloc's refreshToken before dispatching,
  /// so we can detect a successful commit.
  int _tokenBefore = 0;

  @override
  void dispose() {
    _waiverController?.dispose();
    super.dispose();
  }

  List<MemberSummary> get _eligible => widget.candidates
      .where((m) => m.memberId != widget.subjectMemberId)
      .toList();

  Future<List<MemberPickerEntry>> _fetchPage(
    String query,
    int startIndex,
  ) async {
    final q = query.toLowerCase();
    final filtered = q.isEmpty
        ? _eligible
        : _eligible
            .where(
              (m) => m.fullName.toLowerCase().contains(q),
            )
            .toList();
    final end =
        (startIndex + _pageSize).clamp(0, filtered.length);
    if (startIndex >= filtered.length) return const [];
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

  /// Select step → fetch the gym default waiver and advance to the
  /// sign step. No eligibility check — adding is unconditional; the
  /// signed waiver is the only gate.
  Future<void> _continueToSign() async {
    final payer = _selected;
    if (payer == null || _checking) return;
    setState(() {
      _checking = true;
      _checkError = null;
    });
    try {
      final waiver = await _repository.getAuthorizedPayerWaiver(
        widget.subjectMemberId,
      );
      if (!mounted) return;
      setState(() {
        _checking = false;
        _waiverVersionId = waiver.versionId;
        _waiverBody = waiver.body;
        // Built with the payer selected at this point; signer_name re-renders
        // live afterwards (see _onSignChanged).
        _waiverController = _buildWaiverController();
        _step = _LinkStep.sign;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _checkError =
            'We couldn’t load the waiver. Please try again.';
      });
    }
  }

  // Display-only render of the payer-agreement body with the values the
  // backend substitutes at sign time: member_name is the signing payer,
  // payee_name is who they'll pay for, gym_name/date are fixed, and
  // signer_name follows the live typed name (empty stays literal).
  Map<String, String> _renderValues() => {
        kWaiverParamMemberName: _selected?.fullName ?? '',
        kWaiverParamPayeeName: widget.subjectName,
        kWaiverParamGymName: selectedGym.displayName,
        kWaiverParamDate: waiverSignDateUtc(),
        // Empty name -> a literal ___ blank (escaped so markdown never
        // reads it as a rule); fills live once the signer types.
        kWaiverParamSignerName:
            _signerName.isEmpty ? r'\_\_\_' : _signerName,
      };

  QuillController _buildWaiverController() =>
      WaiverMarkdownEditor.controllerFromMarkdown(
        renderWaiverPlaceholders(_waiverBody, _renderValues()),
        readOnly: true,
      );

  // Rebuild the read-only controller on each name keystroke so
  // {{signer_name}} tracks live. Bodies are short — a per-keystroke
  // rebuild is fine.
  void _onSignChanged(String name, bool consent) {
    final nameChanged = name != _signerName;
    setState(() {
      _signerName = name;
      _consent = consent;
      if (nameChanged) {
        _waiverController?.dispose();
        _waiverController = _buildWaiverController();
      }
    });
  }

  bool get _canSign =>
      _consent &&
      _signerName.isNotEmpty &&
      _waiverVersionId != null &&
      !_submitting;

  void _confirmSign() {
    final payer = _selected;
    final versionId = _waiverVersionId;
    if (payer == null || versionId == null || !_canSign) return;
    final bloc = context.read<MemberDetailBloc>();
    final s = bloc.state;
    if (s is MemberDetailLoaded) _tokenBefore = s.refreshToken;
    setState(() => _submitting = true);
    bloc.add(
      LinkParentRequested(
        memberId: widget.subjectMemberId,
        payerMemberId: payer.memberId,
        waiverVersionId: versionId,
        signerName: _signerName,
        consentAcknowledged: true,
      ),
    );
    // Do NOT pop here — BlocConsumer below detects success/failure
    // and transitions to the terminal step.
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
          // Mutation committed — show success terminal step.
          setState(() {
            _submitting = false;
            _step = _LinkStep.success;
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
        return 'Add an authorized payer';
    }
  }

  Widget _selectBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          'Choose who may pay for ${widget.subjectName}. The '
          'payer signs the gym’s authorized-payer waiver next.',
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
            searchLabel: 'Search accounts',
            searchHint: 'Name',
            emptyLabel: 'No eligible accounts.',
            onSelected: (entry) => setState(
              () => _selected = _eligible.firstWhere(
                (m) => m.memberId == entry.id,
              ),
            ),
          ),
        ),
        if (_checkError != null) _ErrorRow(message: _checkError!),
        if (_checking) const Center(child: AppSpinner()),
      ],
    );
  }

  Widget _signBody() {
    final payerName = _selected?.fullName ?? 'The payer';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          '$payerName authorizes paying for ${widget.subjectName}. '
          'Review the waiver, then sign below.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text,
          ),
        ),
        SignWaiverPanel(
          controller: _waiverController!,
          enabled: !_submitting,
          onChanged: _onSignChanged,
        ),
      ],
    );
  }

  Widget _terminalBody(MemberDetailState state) {
    if (_step == _LinkStep.success) {
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
            '${_selected?.fullName ?? 'Payer'} is now authorized '
            'to pay for ${widget.subjectName}.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text,
            ),
          ),
        ],
      );
    }
    // error step
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
          primaryOnPressed: _selected != null && !_checking
              ? _continueToSign
              : null,
          secondaryLabel: 'Cancel',
          secondaryOnPressed: _checking
              ? null
              : () => Navigator.of(context).pop(),
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

class _ErrorRow extends StatelessWidget {
  final String message;

  const _ErrorRow({required this.message});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Icon(
          Symbols.error_sharp,
          size: DesignConstants.iconSizeMedium,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.badRed,
        ),
        Expanded(
          child: Text(
            message,
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.badRed,
            ),
          ),
        ),
      ],
    );
  }
}
