import 'package:flutter/material.dart';

import 'package:crm/features/growth/bloc/growth_state.dart';
import 'package:crm/features/growth/data/models/growth_metric.dart';
import 'package:crm/features/growth/presentation/widgets/growth_range.dart';
import 'package:crm/features/growth/presentation/widgets/growth_tab_body.dart';

/// The Growth page's Members tab.
class MembersTab extends StatelessWidget {
  final GrowthState state;
  final GrowthRange range;
  final bool compact;

  const MembersTab({
    super.key,
    required this.state,
    required this.range,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return GrowthTabBody(
      state: state,
      category: GrowthCategory.members,
      range: range,
      compact: compact,
    );
  }
}
