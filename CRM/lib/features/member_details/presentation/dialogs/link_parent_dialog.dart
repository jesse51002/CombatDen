import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/paginated_member_picker.dart';

/// Picks a paying parent account for a member, runs the
/// backend link eligibility check (`/link/check`), and on
/// success dispatches [LinkParentRequested].
///
/// The picker is fed from the already-loaded roster
/// ([candidates]); the eligibility check goes through a
/// repository built on the shared [ApiClient] (the same
/// construction `auth_gate.dart` / `main.dart` use).
class LinkParentDialog extends StatefulWidget {
  /// The member being linked (the would-be child), or the
  /// parent in the manage-linked-accounts flow when
  /// [childMemberId] is set.
  final String subjectMemberId;

  /// When non-null, links this child to the chosen parent
  /// instead of the viewed member (manage flow).
  final String? childMemberId;

  /// Roster to choose from, minus rows that can't be a
  /// parent (the subject themselves).
  final List<MemberSummary> candidates;

  const LinkParentDialog({
    super.key,
    required this.subjectMemberId,
    required this.candidates,
    this.childMemberId,
  });

  static Future<void> show({
    required BuildContext context,
    required String subjectMemberId,
    required List<MemberSummary> candidates,
    String? childMemberId,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: LinkParentDialog(
          subjectMemberId: subjectMemberId,
          candidates: candidates,
          childMemberId: childMemberId,
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

  /// The id whose link is being created — the child in the
  /// manage flow, otherwise the subject themselves.
  late final String _linkSubjectId =
      widget.childMemberId ?? widget.subjectMemberId;

  MemberSummary? _selected;
  bool _checking = false;
  String? _checkError;

  List<MemberSummary> get _eligible => widget.candidates
      .where((m) => m.memberId != _linkSubjectId)
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

  Future<void> _submit() async {
    final parent = _selected;
    if (parent == null || _checking) return;
    setState(() {
      _checking = true;
      _checkError = null;
    });
    try {
      final check = await _repository.checkLinkMemberAccount(
        _linkSubjectId,
        parent.memberId,
      );
      if (!mounted) return;
      if (!check.canLink) {
        setState(() {
          _checking = false;
          _checkError =
              check.error ?? 'These accounts cannot be linked.';
        });
        return;
      }
      context.read<MemberDetailBloc>().add(
            LinkParentRequested(
              parent.memberId,
              childMemberId: widget.childMemberId,
            ),
          );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _checkError =
            'We couldn’t verify this link. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Link to a paying account',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            'Choose the account that will pay for this '
            'membership. The parent account’s card covers '
            'both.',
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
          if (_checkError != null)
            Row(
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
                    _checkError!,
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.badRed,
                    ),
                  ),
                ),
              ],
            ),
          if (_checking)
            const Center(child: AppSpinner()),
        ],
      ),
      actions: AppDialogActions(
        primaryLabel: 'Link account',
        isLoading: _checking,
        primaryOnPressed:
            _selected != null && !_checking ? _submit : null,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: _checking
            ? null
            : () => Navigator.of(context).pop(),
      ),
    );
  }
}
