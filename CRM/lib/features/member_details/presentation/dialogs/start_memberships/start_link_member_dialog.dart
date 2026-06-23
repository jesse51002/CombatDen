import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/memberships/presentation/widgets/waiver_markdown_editor.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/paginated_member_picker.dart';

enum _LinkStep { select, sign }

/// The wizard's "link first" jump: pick a gym member to authorize the
/// PAYER to pay for, run the backend eligibility check, then have the
/// payer sign the picked member's gym default authorized-payer waiver.
/// On confirm it dispatches [LinkParentRequested] (payee = the pick,
/// payer = the wizard's payer, who signs) and pops with the linked
/// member's id so the wizard refreshes the payer's roster.
///
/// The inverse of [LinkParentDialog] (which picks a payer for the
/// viewed member): here the payer is fixed and the payee is picked.
class StartLinkMemberDialog extends StatefulWidget {
  final String payerMemberId;
  final String payerName;

  /// Roster to choose from; rows already in the payer's
  /// family are excluded by the caller.
  final List<MemberSummary> candidates;

  const StartLinkMemberDialog({
    super.key,
    required this.payerMemberId,
    required this.payerName,
    required this.candidates,
  });

  static Future<String?> show({
    required BuildContext context,
    required String payerMemberId,
    required String payerName,
    required List<MemberSummary> candidates,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: StartLinkMemberDialog(
          payerMemberId: payerMemberId,
          payerName: payerName,
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

  /// Select step → check eligibility, fetch the payee's gym default
  /// waiver, then advance to the sign step.
  Future<void> _continueToSign() async {
    final payee = _selected;
    if (payee == null || _checking) return;
    setState(() {
      _checking = true;
      _checkError = null;
    });
    try {
      final check = await _repository.checkLinkMemberAccount(
        payee.memberId,
        widget.payerMemberId,
      );
      if (!mounted) return;
      if (!check.canLink) {
        setState(() {
          _checking = false;
          _checkError = check.error ??
              'This member cannot be authorized.';
        });
        return;
      }
      final waiver = await _repository.getAuthorizedPayerWaiver(
        payee.memberId,
      );
      if (!mounted) return;
      setState(() {
        _checking = false;
        _waiverController =
            WaiverMarkdownEditor.controllerFromMarkdown(
          waiver.body,
          readOnly: true,
        );
        _signerName.text = widget.payerName;
        _step = _LinkStep.sign;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _checkError = 'We couldn’t verify this link. '
            'Please try again.';
      });
    }
  }

  bool get _canSign =>
      _consent &&
      _signerName.text.trim().isNotEmpty &&
      !_submitting;

  void _confirmSign() {
    final payee = _selected;
    if (payee == null || !_canSign) return;
    setState(() => _submitting = true);
    context.read<MemberDetailBloc>().add(
          LinkParentRequested(
            memberId: payee.memberId,
            payerMemberId: widget.payerMemberId,
            signerName: _signerName.text.trim(),
            consentAcknowledged: true,
          ),
        );
    Navigator.of(context).pop(payee.memberId);
  }

  @override
  Widget build(BuildContext context) {
    final isSign = _step == _LinkStep.sign;
    return AppDialog(
      title: isSign
          ? 'Sign authorized-payer waiver'
          : 'Link a member to ${widget.payerName}',
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
              primaryOnPressed: _selected == null || _checking
                  ? null
                  : _continueToSign,
              secondaryLabel: 'Cancel',
              secondaryOnPressed: () =>
                  Navigator.of(context).pop(),
            ),
    );
  }

  Widget _selectBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          'The picked member joins ${widget.payerName}’s paying '
          'account, so they can be enrolled in this run. The '
          'payer signs their waiver next.',
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
    final payeeName = _selected?.fullName ?? 'this member';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          '${widget.payerName} authorizes paying for $payeeName. '
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
