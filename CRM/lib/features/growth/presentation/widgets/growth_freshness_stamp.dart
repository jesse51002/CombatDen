import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';

/// "Updated hourly · as of 2:00 PM" — when the numbers on screen were
/// computed.
///
/// [computedAt] is the OLDEST surviving metric's compute time by design:
/// the page states the staleness FLOOR, so nothing on it is older than
/// what the stamp claims.
class GrowthFreshnessStamp extends StatelessWidget {
  final DateTime? computedAt;

  const GrowthFreshnessStamp({super.key, required this.computedAt});

  @override
  Widget build(BuildContext context) {
    final at = computedAt;
    if (at == null) return const SizedBox.shrink();
    final local = at.toLocal();
    final withinDay =
        DateTime.now().difference(local).abs() < const Duration(hours: 24);
    final formatted = withinDay
        ? DateFormat.jm().format(local)
        : DateFormat.MMMd().add_jm().format(local);
    return Text(
      'Updated hourly · as of $formatted',
      style: DesignConstants.pSmall.copyWith(
        color: DesignConstants.text3rd,
      ),
    );
  }
}
