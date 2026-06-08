import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/discount_info.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_add_discounts_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_remove_discounts_request.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/presentation/dialogs/manage_discounts_body.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/widgets/invoice_preview_section.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

enum _Step { select, preview }

/// Manages the discounts on a membership line as a two-screen card
/// (Add / Remove), then a **preview** step before committing.
///
/// Each commit is a single operation — the active tab's add **or**
/// remove — because the backend has no combined add+remove. The
/// preview shows the new monthly with per-line was→now (the
/// `recurring` half of [DueNowVsRecurringPreview]); Apply dispatches
/// [AddDiscountsRequested] / [RemoveDiscountsRequested].
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

  /// Applied-discount snapshot ids selected on the Remove screen.
  final Set<String> _toRemove = {};

  /// 0 = Add, 1 = Remove.
  int _tab = 0;

  _Step _step = _Step.select;

  @override
  void initState() {
    super.initState();
    _presets =
        _repository.listGymDiscounts(widget.member.gymId);
  }

  String get _itemId =>
      widget.membership.itemIdFor(widget.coveredMemberId)!;

  /// Snapshots already applied to this member's line — the Remove
  /// screen lists them. Resolved by item.
  List<DiscountInfo> get _applied {
    final itemId =
        widget.membership.itemIdFor(widget.coveredMemberId);
    if (itemId == null) return const [];
    return widget.membership.discounts
        .where((d) => d.itemId == itemId)
        .toList();
  }

  /// Source discount ids of the applied snapshots — hides
  /// already-applied presets from the Add screen.
  Set<String> get _appliedSourceIds => _applied
      .map((d) => d.discountId)
      .whereType<String>()
      .toSet();

  bool get _isAddTab => _tab == 0;

  bool get _hasSelection =>
      _isAddTab ? _toAdd.isNotEmpty : _toRemove.isNotEmpty;

  void _toggle(Set<String> selection, String id) {
    setState(() {
      if (selection.contains(id)) {
        selection.remove(id);
      } else {
        selection.add(id);
      }
    });
  }

  /// Loads the preview for the **active** operation (add or remove).
  Future<DueNowVsRecurringPreview?> _loadPreview() {
    if (_isAddTab) {
      return _repository.addMembershipDiscounts(
        MemberMembershipsAddDiscountsRequest(
          itemId: _itemId,
          memberId: widget.coveredMemberId,
          presetIds: _toAdd.toList(),
          idempotencyKey: const Uuid().v4(),
          preview: true,
        ),
      );
    }
    return _repository.removeMembershipDiscounts(
      MemberMembershipsRemoveDiscountsRequest(
        itemId: _itemId,
        memberId: widget.coveredMemberId,
        appliedIds: _toRemove.toList(),
        idempotencyKey: const Uuid().v4(),
        preview: true,
      ),
    );
  }

  /// Commits the active operation (single op) and closes.
  void _apply() {
    final bloc = context.read<MemberDetailBloc>();
    if (_isAddTab) {
      bloc.add(
        AddDiscountsRequested(
          itemId: _itemId,
          memberId: widget.coveredMemberId,
          presetIds: _toAdd.toList(),
        ),
      );
    } else {
      bloc.add(
        RemoveDiscountsRequested(
          itemId: _itemId,
          memberId: widget.coveredMemberId,
          appliedIds: _toRemove.toList(),
        ),
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isPreview = _step == _Step.preview;
    return AppDialog(
      title: 'Manage discounts',
      body: isPreview ? _previewBody() : _selectBody(),
      actions: isPreview
          ? AppDialogActions(
              primaryLabel: _isAddTab
                  ? 'Apply discounts'
                  : 'Remove discounts',
              primaryOnPressed: _apply,
              secondaryLabel: 'Back',
              secondaryOnPressed: () =>
                  setState(() => _step = _Step.select),
            )
          : AppDialogActions(
              primaryLabel: 'Preview',
              primaryOnPressed: _hasSelection
                  ? () => setState(() => _step = _Step.preview)
                  : null,
              secondaryLabel: 'Cancel',
              secondaryOnPressed: () =>
                  Navigator.of(context).pop(),
            ),
    );
  }

  Widget _selectBody() {
    return FutureBuilder<List<DiscountResponse>>(
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
    );
  }

  Widget _previewBody() {
    // The shared preview viewer: a discount change has no due-now (nothing
    // extra is charged today), so it shows only the recurring section as a
    // current → new comparison.
    return InvoicePreviewSection(
      loadPreview: _loadPreview,
      loadCurrent: () =>
          _repository.getUpcomingInvoice(widget.coveredMemberId),
      showDueNow: false,
      recurringFallbackMonthly:
          widget.member.totalMonthlyRecurringPrice,
      emptyLabel: 'No billing change.',
      errorLabel: 'Could not load the preview.',
    );
  }
}
