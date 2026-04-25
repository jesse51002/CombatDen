import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_preview_section.dart';

/// Picks a paying parent account from the gym's member
/// list and shows a preview of the cost impact before
/// linking.
class LinkParentDialog extends StatefulWidget {
  final String crmUserId;
  final List<MemberSummary> candidates;

  const LinkParentDialog({
    super.key,
    required this.crmUserId,
    required this.candidates,
  });

  static Future<void> show({
    required BuildContext context,
    required String crmUserId,
    required List<MemberSummary> candidates,
  }) {
    final bloc = context.read<MemberDetailBloc>();
    final repository = context.read<MemberRepository>();
    return showDialog<void>(
      context: context,
      builder: (_) => RepositoryProvider.value(
        value: repository,
        child: BlocProvider.value(
          value: bloc,
          child: LinkParentDialog(
            crmUserId: crmUserId,
            candidates: candidates,
          ),
        ),
      ),
    );
  }

  @override
  State<LinkParentDialog> createState() =>
      _LinkParentDialogState();
}

class _LinkParentDialogState extends State<LinkParentDialog> {
  final _search = TextEditingController();
  MemberSummary? _selected;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onConfirm() {
    final selected = _selected;
    if (selected == null) return;
    context
        .read<MemberDetailBloc>()
        .add(LinkParentRequested(selected.crmUserId));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final filtered = widget.candidates
        .where((m) => m.crmUserId != widget.crmUserId)
        .where(
          (m) => query.isEmpty
              ? true
              : m.fullName.toLowerCase().contains(query),
        )
        .take(12)
        .toList();
    final repository = context.read<MemberRepository>();

    return AppDialog(
      title: 'Link to Paying Account',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          CustomTextField(
            controller: _search,
            label: 'Search members',
            hintText: 'Name',
          ),
          Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingSmall,
            children: filtered
                .map(
                  (m) => _ParentTile(
                    member: m,
                    selected:
                        _selected?.crmUserId == m.crmUserId,
                    onTap: () =>
                        setState(() => _selected = m),
                  ),
                )
                .toList(),
          ),
          if (_selected != null)
            InvoicePreviewSection(
              refreshKey: _selected!.crmUserId,
              loadPreview: () =>
                  repository.previewLinkMemberAccount(
                widget.crmUserId,
                _selected!.crmUserId,
              ),
            ),
        ],
      ),
      actions: AppDialogActions(
        primaryLabel: 'Link Account',
        primaryOnPressed:
            _selected != null ? _onConfirm : null,
        secondaryLabel: 'Cancel',
      ),
    );
  }
}

class _ParentTile extends StatelessWidget {
  final MemberSummary member;
  final bool selected;
  final VoidCallback onTap;

  const _ParentTile({
    required this.member,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: Container(
        padding: const EdgeInsets.all(
          DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          color: selected
              ? DesignConstants.primaryColor
                  .withValues(alpha: 0.12)
              : DesignConstants.backgroundColor,
          border: Border.all(
            color: selected
                ? DesignConstants.primaryColor
                : DesignConstants.divider,
          ),
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
        ),
        child: Text(
          member.fullName,
          style: DesignConstants.p,
        ),
      ),
    );
  }
}
