import 'package:flutter/material.dart';

import 'package:mobile_app/core/design_constants.dart';

// Drag-handle geometry — pure layout math for one bar, not design tokens.
const double _kHandleWidth = 36;
const double _kHandleHeight = 4;

/// The app's ONE modal bottom sheet. Every sheet goes through here so they all
/// share the same surface as `SignOutDialog` — `popup` fill, `radiusBig` on the
/// top corners, `paddingSmall` inset — and read as the same family of
/// temporary surfaces.
///
/// `isScrollControlled` so a tall sheet (a long profile list) can grow past the
/// half-screen default and still scroll.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DesignConstants.popup,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(DesignConstants.radiusBig),
      ),
    ),
    builder: (context) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.all(DesignConstants.paddingSmall),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingLarge,
          children: [
            const _DragHandle(),
            Flexible(child: builder(context)),
          ],
        ),
      ),
    ),
  );
}

/// The grab affordance. Decorative — the sheet is dismissed by swipe or scrim
/// tap, both of which a screen reader reaches without this bar.
class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Center(
        child: Container(
          width: _kHandleWidth,
          height: _kHandleHeight,
          decoration: BoxDecoration(
            color: DesignConstants.text3rd,
            borderRadius: BorderRadius.circular(DesignConstants.radiusCircle),
          ),
        ),
      ),
    );
  }
}
