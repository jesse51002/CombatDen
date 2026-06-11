import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/paginated_member_picker.dart';

/// The wizard's "link first" jump: pick a gym member to
/// link to the PAYER, run the backend link eligibility
/// check, then dispatch [LinkParentRequested] (the existing
/// link path — parent = the payer, child = the pick). Pops
/// with the linked member's id so the wizard can refresh
/// the payer's family and show the new member in step 2.
///
/// The inverse of [LinkParentDialog] (which picks a parent
/// for the viewed member): here the parent is fixed and the
/// child is picked.
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

  MemberSummary? _selected;
  bool _checking = false;
  String? _checkError;

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

  Future<void> _submit() async {
    final child = _selected;
    if (child == null || _checking) return;
    setState(() {
      _checking = true;
      _checkError = null;
    });
    try {
      final check =
          await _repository.checkLinkMemberAccount(
        child.memberId,
        widget.payerMemberId,
      );
      if (!mounted) return;
      if (!check.canLink) {
        setState(() {
          _checking = false;
          _checkError = check.error ??
              'These accounts cannot be linked.';
        });
        return;
      }
      context.read<MemberDetailBloc>().add(
            LinkParentRequested(
              widget.payerMemberId,
              childMemberId: child.memberId,
            ),
          );
      Navigator.of(context).pop(child.memberId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _checkError = 'We couldn’t verify this link. '
            'Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Link a member to ${widget.payerName}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            'The picked member joins '
            '${widget.payerName}’s paying account, so '
            'they can be enrolled in this run.',
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
                  _selected = match.isEmpty
                      ? null
                      : match.first;
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
      ),
      actions: AppDialogActions(
        primaryLabel: 'Link member',
        isLoading: _checking,
        primaryOnPressed:
            _selected == null || _checking
                ? null
                : _submit,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () =>
            Navigator.of(context).pop(),
      ),
    );
  }
}
