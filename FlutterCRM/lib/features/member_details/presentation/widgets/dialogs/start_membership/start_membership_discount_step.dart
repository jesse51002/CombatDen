import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/shared/widgets/discount_grid.dart';

/// Step 2 — optionally apply one or more gym discounts
/// to the new membership. Skippable. Multi-select.
class StartMembershipDiscountStep extends StatefulWidget {
  final String gymId;
  final Set<String> selected;
  final void Function(String id, bool selected) onToggle;

  const StartMembershipDiscountStep({
    super.key,
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
    _future = context
        .read<MemberRepository>()
        .listGymDiscounts(widget.gymId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DiscountResponse>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState !=
            ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(
              DesignConstants.spacingLarge,
            ),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        final discounts = snapshot.data ?? [];
        if (discounts.isEmpty) {
          return Text(
            'No gym discounts configured. Skip this step.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          );
        }
        return DiscountGrid(
          discounts: discounts,
          selectedIds: widget.selected,
          onTap: (d) => widget.onToggle(
            d.discountId,
            !widget.selected.contains(d.discountId),
          ),
        );
      },
    );
  }
}
