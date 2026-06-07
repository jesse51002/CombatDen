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

/// Manages the discounts on a membership line as a two-screen
/// card: an **Add** screen (the gym's not-yet-applied presets)
/// and a **Remove** screen (the snapshots already applied to
/// this member's line). Both selections commit together in a
/// single [ApplyDiscountsRequested] — an explicit add / remove
/// of immutable snapshot rows, never a replace-set.
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

  /// Preset discount ids selected on the Add screen.
  final Set<String> _toAdd = {};

  /// Applied-discount snapshot ids selected on the Remove
  /// screen.
  final Set<String> _toRemove = {};

  /// 0 = Add screen, 1 = Remove screen.
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _presets =
        _repository.listGymDiscounts(widget.member.gymId);
  }

  /// Snapshots already applied to this member's line — the
  /// Remove screen lists them. Resolved by item.
  List<DiscountInfo> get _applied {
    final itemId =
        widget.membership.itemIdFor(widget.coveredMemberId);
    if (itemId == null) return const [];
    return widget.membership.discounts
        .where((d) => d.itemId == itemId)
        .toList();
  }

  /// Source discount ids of the applied snapshots — used to
  /// hide already-applied presets from the Add screen.
  Set<String> get _appliedSourceIds => _applied
      .map((d) => d.discountId)
      .whereType<String>()
      .toSet();

  void _toggle(Set<String> selection, String id) {
    setState(() {
      if (selection.contains(id)) {
        selection.remove(id);
      } else {
        selection.add(id);
      }
    });
  }

  /// Commits the Add and Remove selections together in one
  /// request, then closes. A no-op (just close) when nothing
  /// is selected on either screen.
  void _submit() {
    if (_toAdd.isEmpty && _toRemove.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
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
            addPresetIds: _toAdd.toList(),
            removeAppliedIds: _toRemove.toList(),
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
            selectedToRemove: _toRemove,
            activeTab: _tab,
            onTabChanged: (i) => setState(() => _tab = i),
            onToggleAdd: (id) => _toggle(_toAdd, id),
            onToggleRemove: (id) => _toggle(_toRemove, id),
          );
        },
      ),
      actions: AppDialogActions(
        primaryLabel: 'Apply changes',
        primaryOnPressed: _submit,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () =>
            Navigator.of(context).pop(),
      ),
    );
  }
}
