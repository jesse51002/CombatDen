import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/stripe_coupon_duration.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/discount_grid.dart';

/// Manages the full discount set on a membership: loads the
/// gym's discounts, pre-selects the ones already applied, and
/// dispatches [UpdateDiscountsRequested] with the complete
/// replacement set (the merged endpoint replaces, not
/// appends).
class ManageDiscountsDialog extends StatefulWidget {
  final String gymId;
  final MembershipInfo membership;
  final String coveredMemberId;

  const ManageDiscountsDialog({
    super.key,
    required this.gymId,
    required this.membership,
    required this.coveredMemberId,
  });

  static Future<void> show({
    required BuildContext context,
    required String gymId,
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
          gymId: gymId,
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

  late Future<List<DiscountResponse>> _future;
  final Set<String> _selected = {};
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    _selected.addAll(
      widget.membership.discounts.map((d) => d.discountId),
    );
    _seeded = true;
    _future = _repository.listGymDiscounts(widget.gymId);
  }

  String? _durationLabel(DiscountResponse d) {
    switch (d.duration) {
      case StripeCouponDuration.once:
        return 'Once';
      case StripeCouponDuration.forever:
        return 'Forever';
      case StripeCouponDuration.repeating:
        final months = d.durationInMonths;
        return months == null
            ? 'Repeating'
            : 'For $months months';
      case StripeCouponDuration.unknown:
        return null;
    }
  }

  void _submit() {
    final itemId =
        widget.membership.itemIdFor(widget.coveredMemberId);
    if (itemId == null) {
      Navigator.of(context).pop();
      return;
    }
    context.read<MemberDetailBloc>().add(
          UpdateDiscountsRequested(
            itemId: itemId,
            memberId: widget.coveredMemberId,
            discountIds: _selected.toList(),
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Manage discounts',
      body: FutureBuilder<List<DiscountResponse>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState !=
              ConnectionState.done) {
            return const SizedBox(
              height: 160,
              child: Center(child: AppSpinner()),
            );
          }
          if (snapshot.hasError) {
            return _ErrorText(
              message:
                  'Couldn’t load discounts. Please try again.',
            );
          }
          final discounts = snapshot.data ?? const [];
          if (discounts.isEmpty) {
            return _ErrorText(
              message:
                  'This gym has no discounts set up yet.',
            );
          }
          // Keep already-applied ids that may no longer be in
          // the gym list selected so a save doesn't silently
          // drop them.
          final knownIds =
              discounts.map((d) => d.discountId).toSet();
          if (_seeded) {
            _selected.removeWhere(
              (id) => !knownIds.contains(id),
            );
            _seeded = false;
          }
          final options = discounts
              .map(
                (d) => DiscountOption(
                  id: d.discountId,
                  name: d.discountName,
                  valueLabel: d.displayLabel,
                  durationLabel: _durationLabel(d),
                ),
              )
              .toList();
          return DiscountGrid(
            discounts: options,
            selectedIds: _selected,
            onToggle: (d) => setState(() {
              if (_selected.contains(d.id)) {
                _selected.remove(d.id);
              } else {
                _selected.add(d.id);
              }
            }),
          );
        },
      ),
      actions: AppDialogActions(
        primaryLabel: 'Save discounts',
        primaryOnPressed: _submit,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () =>
            Navigator.of(context).pop(),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  final String message;

  const _ErrorText({required this.message});

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: DesignConstants.p.copyWith(
        color: DesignConstants.text2nd,
      ),
    );
  }
}
