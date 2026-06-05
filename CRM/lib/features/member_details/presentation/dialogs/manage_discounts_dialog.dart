import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/discount_info.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/dialogs/manage_discounts_body.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Adds discounts to a membership: lists the gym's regular
/// presets to add, shows the snapshots already applied to
/// this member's line (frozen, removed from their own row in
///
/// Applying is add-only here: dispatches
/// [ApplyDiscountsRequested] with the newly-selected preset
/// ids. Removal happens
/// per-snapshot from the section's table (never a
/// replace-set).
class ManageDiscountsDialog extends StatefulWidget {
  final MemberDetailResponse member;
  final MembershipInfo membership;
  final String coveredMemberId;

  const ManageDiscountsDialog({
    super.key,
    required this.member,
    required this.membership,
    required this.coveredMemberId,
  });

  static Future<void> show({
    required BuildContext context,
    required MemberDetailResponse member,
    required MembershipInfo membership,
    required String coveredMemberId,
  }) {
    if (membership.itemIdFor(coveredMemberId) == null) {
      return Future.value();
    }
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: ManageDiscountsDialog(
          member: member,
          membership: membership,
          coveredMemberId: coveredMemberId,
        ),
      ),
    );
  }

  @override
  State<ManageDiscountsDialog> createState() =>
      _ManageDiscountsDialogState();
}

class _ManageDiscountsDialogState
    extends State<ManageDiscountsDialog> {
  final MemberRepository _repository =
      MemberRepository(apiClient: ApiClient());

  late Future<List<DiscountResponse>> _presets;
  final Set<String> _toAdd = {};

  @override
  void initState() {
    super.initState();
    _presets =
        _repository.listGymDiscounts(widget.member.gymId);
  }

  /// Snapshots already applied to this member's line — shown
  /// read-only so staff don't double-add. Resolved by item.
  List<DiscountInfo> get _applied {
    final itemId =
        widget.membership.itemIdFor(widget.coveredMemberId);
    if (itemId == null) return const [];
    return widget.membership.discounts
        .where((d) => d.itemId == itemId)
        .toList();
  }

  Set<String> get _appliedSourceIds => _applied
      .map((d) => d.discountId)
      .whereType<String>()
      .toSet();

  void _submit() {
    if (_toAdd.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    _dispatch(presetIds: _toAdd.toList());
  }

  void _dispatch({
    List<String> presetIds = const [],
  }) {
    final itemId =
        widget.membership.itemIdFor(widget.coveredMemberId);
    if (itemId == null) {
      Navigator.of(context).pop();
      return;
    }
    context.read<MemberDetailBloc>().add(
          ApplyDiscountsRequested(
            itemId: itemId,
            memberId: widget.coveredMemberId,
            addPresetIds: presetIds,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Manage discounts',
      body: FutureBuilder<List<DiscountResponse>>(
        future: _presets,
        builder: (context, snapshot) {
          if (snapshot.connectionState !=
              ConnectionState.done) {
            return const SizedBox(
              height: 160,
              child: Center(child: AppSpinner()),
            );
          }
          return ManageDiscountsBody(
            presets: snapshot.hasError
                ? const []
                : (snapshot.data ?? const []),
            loadFailed: snapshot.hasError,
            appliedSourceIds: _appliedSourceIds,
            appliedDiscounts: _applied,
            selectedToAdd: _toAdd,
            onToggle: (id) => setState(() {
              if (_toAdd.contains(id)) {
                _toAdd.remove(id);
              } else {
                _toAdd.add(id);
              }
            }),
          );
        },
      ),
      actions: AppDialogActions(
        primaryLabel: 'Apply discounts',
        primaryOnPressed: _submit,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () =>
            Navigator.of(context).pop(),
      ),
    );
  }
}
