import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/members_management_link_check_response.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_preview_section.dart';
import 'package:crm/shared/widgets/paginated_member_picker.dart';

/// Two-step: pick a candidate account, then validate via
/// `/link/check` and confirm linking it to the paying parent.
class LinkChildDialog extends StatefulWidget {
  final String parentCrmUserId;
  final String gymId;

  const LinkChildDialog({
    super.key,
    required this.parentCrmUserId,
    required this.gymId,
  });

  static Future<void> show({
    required BuildContext context,
    required String parentCrmUserId,
    required String gymId,
  }) {
    final bloc = context.read<MemberDetailBloc>();
    final repository = context.read<MemberRepository>();
    return showDialog<void>(
      context: context,
      builder: (_) => RepositoryProvider.value(
        value: repository,
        child: BlocProvider.value(
          value: bloc,
          child: LinkChildDialog(
            parentCrmUserId: parentCrmUserId,
            gymId: gymId,
          ),
        ),
      ),
    );
  }

  @override
  State<LinkChildDialog> createState() =>
      _LinkChildDialogState();
}

enum _Step { pick, confirm }

class _LinkChildDialogState extends State<LinkChildDialog> {
  _Step _step = _Step.pick;
  MemberRow? _selected;
  Future<MembersManagementLinkCheckResponse>? _checkFuture;

  void _onPick(MemberRow row) {
    setState(() {
      _selected = row;
      _step = _Step.confirm;
      _checkFuture = context
          .read<MemberRepository>()
          .checkLinkMemberAccount(
            row.crmUserId,
            widget.parentCrmUserId,
          );
    });
  }

  void _onBack() {
    setState(() {
      _selected = null;
      _checkFuture = null;
      _step = _Step.pick;
    });
  }

  void _onConfirm() {
    final selected = _selected;
    if (selected == null) return;
    context.read<MemberDetailBloc>().add(
          LinkParentRequested(
            widget.parentCrmUserId,
            childCrmUserId: selected.crmUserId,
          ),
        );
    Navigator.of(context)
      ..pop()
      ..pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_step == _Step.pick) {
      return AppDialog(
        title: 'Link New Account',
        body: PaginatedMemberPicker(
          gymId: widget.gymId,
          onSelected: _onPick,
        ),
        actions: const AppDialogActions(
          primaryLabel: 'Cancel',
        ),
      );
    }
    return FutureBuilder<MembersManagementLinkCheckResponse>(
      future: _checkFuture,
      builder: (context, snapshot) {
        final done =
            snapshot.connectionState == ConnectionState.done;
        final check = snapshot.data;
        final canLink = done && check?.canLink == true;
        return AppDialog(
          title: 'Confirm Link Account',
          body: _ConfirmBody(
            candidate: _selected!,
            parentCrmUserId: widget.parentCrmUserId,
            snapshot: snapshot,
          ),
          actions: AppDialogActions(
            primaryLabel: 'Link Account',
            primaryColor: DesignConstants.primaryColor,
            primaryOnPressed: canLink ? _onConfirm : null,
            secondaryLabel: 'Back',
            secondaryOnPressed: _onBack,
          ),
        );
      },
    );
  }
}

class _ConfirmBody extends StatelessWidget {
  final MemberRow candidate;
  final String parentCrmUserId;
  final AsyncSnapshot<MembersManagementLinkCheckResponse>
      snapshot;

  const _ConfirmBody({
    required this.candidate,
    required this.parentCrmUserId,
    required this.snapshot,
  });

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Padding(
        padding: EdgeInsets.all(
          DesignConstants.spacingLarge,
        ),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (snapshot.hasError) {
      return Text(
        'Could not check link eligibility.',
        style: DesignConstants.p.copyWith(
          color: DesignConstants.badRed,
        ),
      );
    }
    final check = snapshot.data!;
    if (!check.canLink) {
      return Text(
        check.error ?? 'This account cannot be linked.',
        style: DesignConstants.p.copyWith(
          color: DesignConstants.badRed,
        ),
      );
    }
    final repository = context.read<MemberRepository>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          '${candidate.name} will be linked to this paying '
          'account. Their next bill will be charged to the '
          'payer on file.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        InvoicePreviewSection(
          refreshKey: candidate.crmUserId,
          loadPreview: () =>
              repository.previewLinkMemberAccount(
            candidate.crmUserId,
            parentCrmUserId,
          ),
        ),
      ],
    );
  }
}
