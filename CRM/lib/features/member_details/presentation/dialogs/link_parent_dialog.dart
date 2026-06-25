import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/memberships/presentation/widgets/waiver_markdown_editor.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/paginated_member_picker.dart';

enum _LinkStep { select, sign }

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
  final TextEditingController _signerName = TextEditingController();
  bool _consent = false;
  bool _submitting = false;

  @override
  void dispose() {
    _signerName.dispose();
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
        _waiverController =
            WaiverMarkdownEditor.controllerFromMarkdown(
          waiver.body,
          readOnly: true,
        );
        // Never pre-fill the signature — the payer must type their
        // own name; a pre-filled field is not a signature.
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

  bool get _canSign =>
      _consent &&
      _signerName.text.trim().isNotEmpty &&
      !_submitting;

  void _confirmSign() {
    final payer = _selected;
    if (payer == null || !_canSign) return;
    setState(() => _submitting = true);
    context.read<MemberDetailBloc>().add(
          LinkParentRequested(
            memberId: widget.subjectMemberId,
            payerMemberId: payer.memberId,
            signerName: _signerName.text.trim(),
            consentAcknowledged: true,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isSign = _step == _LinkStep.sign;
    return AppDialog(
      title: isSign
          ? 'Sign authorized-payer waiver'
          : 'Add an authorized payer',
      body: isSign ? _signBody() : _selectBody(),
      actions: isSign
          ? AppDialogActions(
              primaryLabel: 'Authorize payer',
              isLoading: _submitting,
              primaryOnPressed: _canSign ? _confirmSign : null,
              secondaryLabel: 'Back',
              secondaryOnPressed: _submitting
                  ? null
                  : () => setState(() => _step = _LinkStep.select),
            )
          : AppDialogActions(
              primaryLabel: 'Continue',
              isLoading: _checking,
              primaryOnPressed: _selected != null && !_checking
                  ? _continueToSign
                  : null,
              secondaryLabel: 'Cancel',
              secondaryOnPressed: _checking
                  ? null
                  : () => Navigator.of(context).pop(),
            ),
    );
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
          height: 320,
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
        SizedBox(
          height: 240,
          child: WaiverMarkdownEditor(
            controller: _waiverController!,
          ),
        ),
        TextField(
          controller: _signerName,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Type full name to sign',
          ),
        ),
        InkWell(
          onTap: () => setState(() => _consent = !_consent),
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingSmall,
            children: [
              Checkbox(
                value: _consent,
                onChanged: (v) =>
                    setState(() => _consent = v ?? false),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: DesignConstants.spacingMedium,
                  ),
                  child: Text(
                    'I, the payer, have read and agree to the '
                    'waiver above.',
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
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
