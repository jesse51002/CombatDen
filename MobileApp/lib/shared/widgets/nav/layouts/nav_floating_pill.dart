import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/nav/app_nav_item.dart';

const double _kPillHeight = 56;

/// An inset, rounded nav bar floating over the canvas.
///
/// Labels are not laid out here, but every item still builds its label
/// and still announces it (see `AppNavItem.showLabel`), so no target
/// loses its accessible name.
class NavFloatingPill extends StatelessWidget {
  const NavFloatingPill({super.key, required this.items});

  final List<AppNavItem> items;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: DesignConstants.spacingBig,
        right: DesignConstants.spacingBig,
        bottom: bottomInset + DesignConstants.spacingMedium,
      ),
      child: Container(
        height: _kPillHeight,
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(_kPillHeight / 2),
          border: Border.all(
            color: DesignConstants.divider,
            width: DesignConstants.dividerThickness,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [for (final item in items) Expanded(child: item)],
        ),
      ),
    );
  }
}
