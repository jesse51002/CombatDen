import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_preview_section.dart';

/// Confirms unlinking a member from their paying parent.
/// Enforces the backend rule ("no active recurring
/// memberships on the child") up-front — the button stays
/// disabled until every blocking membership is cancelled,
/// so the staff member never lands on a raw validation
/// error from the API.
class UnlinkParentDialog extends StatefulWidget {
  final String crmUserId;

  const UnlinkParentDialog({
    super.key,
    required this.crmUserId,
  });

  static Future<void> show({
    required BuildContext context,
    required String crmUserId,
  }) {
    final bloc = context.read<MemberDetailBloc>();
    final repository = context.read<MemberRepository>();
    return showDialog<void>(
      context: context,
      builder: (_) => RepositoryProvider.value(
        value: repository,
        child: BlocProvider.value(
          value: bloc,
          child: UnlinkParentDialog(crmUserId: crmUserId),
        ),
      ),
    );
  }

  @override
  State<UnlinkParentDialog> createState() =>
      _UnlinkParentDialogState();
}

class _UnlinkParentDialogState
    extends State<UnlinkParentDialog> {
  late Future<MemberDetailResponse> _future;

  @override
  void initState() {
    super.initState();
    _future = context
        .read<MemberRepository>()
        .getMemberDetail(widget.crmUserId);
  }

  void _onConfirm() {
    context.read<MemberDetailBloc>().add(
          UnlinkParentRequested(
            childCrmUserId: widget.crmUserId,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MemberDetailResponse>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState !=
            ConnectionState.done) {
          return const AppDialog(
            title: 'Unlink from Paying Account',
            body: Padding(
              padding: EdgeInsets.all(
                DesignConstants.spacingLarge,
              ),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return AppDialog(
            title: 'Unlink from Paying Account',
            body: Text(
              'Could not load member: '
              '${snapshot.error ?? 'unknown error'}',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.badRed,
              ),
            ),
            actions: AppDialogActions(
              primaryLabel: 'Close',
              primaryOnPressed: () =>
                  Navigator.of(context).pop(),
            ),
          );
        }
        final member = snapshot.data!;
        final blocking = _blockingMemberships(member);
        final canUnlink = blocking.isEmpty;
        return AppDialog(
          title: 'Unlink from Paying Account',
          body: _UnlinkBody(
            member: member,
            blocking: blocking,
            canUnlink: canUnlink,
          ),
          actions: AppDialogActions(
            primaryLabel: 'Unlink',
            primaryColor: DesignConstants.badRed,
            primaryOnPressed:
                canUnlink ? _onConfirm : null,
            secondaryLabel: 'Cancel',
          ),
        );
      },
    );
  }

  List<MembershipInfo> _blockingMemberships(
    MemberDetailResponse member,
  ) {
    return member.memberships
        .where(
          (m) =>
              m.planType == 'recurring' &&
              const {
                MembershipStatus.active,
                MembershipStatus.trial,
                MembershipStatus.frozen,
                MembershipStatus.overdue,
              }.contains(m.status),
        )
        .toList();
  }
}

class _UnlinkBody extends StatelessWidget {
  final MemberDetailResponse member;
  final List<MembershipInfo> blocking;
  final bool canUnlink;

  const _UnlinkBody({
    required this.member,
    required this.blocking,
    required this.canUnlink,
  });

  @override
  Widget build(BuildContext context) {
    final repository = context.read<MemberRepository>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          '${member.fullName} will pay for their own '
          'memberships going forward.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        _BlockingRulesBlock(
          memberName: member.fullName,
          blocking: blocking,
        ),
        if (canUnlink)
          InvoicePreviewSection(
            loadPreview: () =>
                repository.previewUnlinkMemberAccount(
              member.crmUserId,
            ),
          ),
      ],
    );
  }
}

class _BlockingRulesBlock extends StatelessWidget {
  final String memberName;
  final List<MembershipInfo> blocking;

  const _BlockingRulesBlock({
    required this.memberName,
    required this.blocking,
  });

  @override
  Widget build(BuildContext context) {
    if (blocking.isEmpty) {
      return _InfoRow(
        icon: Symbols.check_circle_sharp,
        color: DesignConstants.goodGreen,
        text: 'No active recurring memberships on '
            '$memberName — ready to unlink.',
      );
    }
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(color: DesignConstants.badRed),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingSmall,
        children: [
          _InfoRow(
            icon: Symbols.block_sharp,
            color: DesignConstants.badRed,
            text: 'Cancel every active recurring '
                'membership on $memberName before '
                'unlinking.',
          ),
          ...blocking.map(
            (m) => Padding(
              padding: const EdgeInsets.only(
                left: DesignConstants.spacingLarge,
              ),
              child: Text(
                '• ${m.planName} '
                '(${m.status.displayLabel})',
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _InfoRow({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Icon(
          icon,
          size: 20,
          color: color,
          weight: DesignConstants.iconWeight,
        ),
        Expanded(
          child: Text(
            text,
            style: DesignConstants.pSmall.copyWith(
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
