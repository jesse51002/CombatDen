import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';

/// Empty state for the pick-class step: the gym has no classes on the board
/// today, so there's nothing to check into.
class PickClassEmptyView extends StatelessWidget {
  const PickClassEmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(DesignConstants.paddingBig),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingBig,
          children: [
            Icon(
              Symbols.event_busy_sharp,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.text2nd,
              size: DesignConstants.iconSize2xl,
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingMedium,
              children: [
                Text(
                  'No classes today',
                  textAlign: TextAlign.center,
                  style: DesignConstants.h1,
                ),
                Text(
                  "There's nothing on the schedule to check into right now.",
                  textAlign: TextAlign.center,
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
