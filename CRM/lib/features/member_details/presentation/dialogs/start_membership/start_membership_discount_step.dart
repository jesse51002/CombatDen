import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/stripe_coupon_duration.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/discount_grid.dart';

/// Step 2 — optionally apply one or more gym discounts to
/// the new membership. Skippable. Multi-select. Selected
/// ids flow into the charge preview on the review step.
class StartMembershipDiscountStep extends StatefulWidget {
  final MemberRepository repository;
  final String gymId;
  final Set<String> selected;
  final void Function(String id, bool selected) onToggle;

  const StartMembershipDiscountStep({
    super.key,
    required this.repository,
    required this.gymId,
    required this.selected,
    required this.onToggle,
  });

  @override
  State<StartMembershipDiscountStep> createState() =>
      _StartMembershipDiscountStepState();
}

class _StartMembershipDiscountStepState
    extends State<StartMembershipDiscountStep> {
  late Future<List<DiscountResponse>> _future;

  @override
  void initState() {
    super.initState();
    _future =
        widget.repository.listGymDiscounts(widget.gymId);
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DiscountResponse>>(
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
          return Text(
            'Couldn’t load discounts. You can skip this '
            'step.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          );
        }
        final discounts = snapshot.data ?? const [];
        if (discounts.isEmpty) {
          return Text(
            'This gym has no discounts set up. Skip this '
            'step.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          );
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
          selectedIds: widget.selected,
          onToggle: (d) => widget.onToggle(
            d.id,
            !widget.selected.contains(d.id),
          ),
        );
      },
    );
  }
}
