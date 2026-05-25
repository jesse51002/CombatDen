import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// A horizontally-scrolling row that actually scrolls on desktop web:
/// mouse click-drag is enabled (Flutter disables it by default) and a
/// scrollbar is always visible so the overflow to the right is obvious.
class HorizontalScroller extends StatefulWidget {
  final List<Widget> children;
  final double spacing;

  const HorizontalScroller({
    super.key,
    required this.children,
    this.spacing = DesignConstants.spacingLarge,
  });

  @override
  State<HorizontalScroller> createState() => _HorizontalScrollerState();
}

class _HorizontalScrollerState extends State<HorizontalScroller> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const _DragScrollBehavior(),
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: DesignConstants.spacingBig),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: widget.spacing,
            children: widget.children,
          ),
        ),
      ),
    );
  }
}

/// Lets a mouse (and trackpad/stylus) drag-scroll, not just touch.
class _DragScrollBehavior extends MaterialScrollBehavior {
  const _DragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}
