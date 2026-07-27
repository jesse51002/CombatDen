import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/nav/app_nav_item.dart';

const double _kBottomNavRowHeight = 64;

/// The four-up bottom nav that ships today: a full-width row of equal
/// icon-over-label targets above a hairline rule.
class NavFourUp extends StatelessWidget {
  const NavFourUp({super.key, required this.items});

  /// Already-built nav items, in fixed tab order.
  final List<AppNavItem> items;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        border: Border(
          top: BorderSide(
            color: DesignConstants.text3rd,
            width: DesignConstants.dividerThickness,
          ),
        ),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: _kBottomNavRowHeight,
        child: Row(
          children: [for (final item in items) Expanded(child: item)],
        ),
      ),
    );
  }
}
