import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/dialogs/end_membership_success_view.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

enum _Step { confirm, processing, success }

/// Confirms ending a ONE-TIME / TRIAL membership early (sets the end date
/// to today → 'ended'; no money moves). Submitting drives an in-dialog
/// spinner → success step; the outcome rides the bloc's dedicated end
/// channel ([isEnding] / [endSuccess] / [endError]) so the screen-level
/// overlay + error dialog never fire while this dialog is open (mirrors the
/// upgrade dialog).
class EndMembershipDialog extends StatefulWidget {
  final MembershipInfo membership;
  final String coveredMemberId;
  final String coveredMemberName;

  const EndMembershipDialog({
    super.key,
    required this.membership,
    required this.coveredMemberId,
    required this.coveredMemberName,
  });

  static Future<void> show({
    required BuildContext context,
    required MembershipInfo membership,
    required String coveredMemberId,
    required String coveredMemberName,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: EndMembershipDialog(
          membership: membership,
          coveredMemberId: coveredMemberId,
          coveredMemberName: coveredMemberName,
        ),
      ),
    );
  }

  @override
  State<EndMembershipDialog> createState() => _EndMembershipDialogState();
}

class _EndMembershipDialogState extends State<EndMembershipDialog> {
  late final MemberDetailBloc _bloc;
  late final int _successTokenAtOpen;
  _Step _step = _Step.confirm;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bloc = context.read<MemberDetailBloc>();
    final st = _bloc.state;
    _successTokenAtOpen =
        st is MemberDetailLoaded ? st.endSuccess : 0;
    // Clear any prior end error so a stale failure never flashes.
    _bloc.add(const EndMembershipOutcomeCleared());
  }

  void _submit() {
    setState(() {
      _error = null;
      _step = _Step.processing;
    });
    _bloc.add(
      EndMembershipRequested(
        itemId: widget.membership.itemId,
        memberId: widget.coveredMemberId,
      ),
    );
  }

  void _onState(BuildContext context, MemberDetailState state) {
    if (state is! MemberDetailLoaded) return;
    if (_step != _Step.processing) return;
    final err = state.endError;
    if (err != null) {
      setState(() {
        _error = err;
        _step = _Step.confirm;
      });
      _bloc.add(const EndMembershipOutcomeCleared());
      return;
    }
    if (state.endSuccess != _successTokenAtOpen) {
      setState(() => _step = _Step.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MemberDetailBloc, MemberDetailState>(
      listenWhen: (prev, curr) => curr is MemberDetailLoaded,
      listener: _onState,
      child: AppDialog(
        title: 'End membership',
        showCloseButton: _step != _Step.processing,
        body: _buildBody(),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _Step.confirm:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingMedium,
          children: [
            Text(
              'End ${widget.coveredMemberName}’s '
              '${widget.membership.planName} now? It will be marked '
              'ended and lose access. This does not refund any payment '
              '— use Refund for that.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text,
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.badRed,
                ),
              ),
          ],
        );
      case _Step.processing:
        return const _EndProcessing();
      case _Step.success:
        return EndMembershipSuccessView(
          memberName: widget.coveredMemberName,
          planName: widget.membership.planName,
        );
    }
  }

  Widget _buildActions() {
    switch (_step) {
      case _Step.confirm:
        return AppDialogActions(
          primaryLabel: 'End membership',
          primaryColor: DesignConstants.badRed,
          primaryOnPressed: _submit,
          secondaryLabel: 'Cancel',
          secondaryOnPressed: () => Navigator.of(context).pop(),
        );
      case _Step.processing:
        return const AppDialogActions(
          primaryLabel: 'End membership',
          isLoading: true,
          primaryOnPressed: null,
        );
      case _Step.success:
        return AppDialogActions(
          primaryLabel: 'Done',
          primaryOnPressed: () => Navigator.of(context).pop(),
        );
    }
  }
}

class _EndProcessing extends StatelessWidget {
  const _EndProcessing();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DesignConstants.dialogProcessingHeight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            const AppSpinner(),
            Text(
              'Ending…',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
