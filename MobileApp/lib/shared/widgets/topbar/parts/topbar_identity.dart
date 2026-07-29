import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/gym_mark.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/gym_name_label.dart';
import 'package:mobile_app/shared/widgets/topbar/topbar_data.dart';

/// The tappable gym identity: mark and/or name plus the switch chevron.
///
/// [markSize] null means "no mark" — which is how a layout honours
/// `AppTopbarMode.nameOnly`, the shipped behaviour on every screen
/// except home.
class TopbarIdentity extends StatelessWidget {
  const TopbarIdentity({
    super.key,
    required this.data,
    required this.markSize,
    required this.axis,
    this.nameStyle,
    this.nameHidden = false,
  });

  final TopbarData data;
  final GymMarkSize? markSize;
  final Axis axis;
  final TextStyle? nameStyle;
  final bool nameHidden;

  @override
  Widget build(BuildContext context) {
    final mark = markSize == null
        ? null
        : GymMark(logoAsset: data.logoAsset, size: markSize!);
    final name = GymNameLabel(
      gymName: data.gymName,
      style: nameStyle,
      visuallyHidden: nameHidden,
    );

    // On a single-row topbar the name must be able to give up width,
    // or a long gym name pushes the stat cluster off the screen. The
    // label ellipsises internally once it is constrained.
    final children = <Widget>[
      ?mark,
      axis == Axis.horizontal ? Flexible(child: name) : name,
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: data.onTitleTap,
      onDoubleTap: data.onTitleDoubleTap,
      child: axis == Axis.vertical
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: DesignConstants.spacingBig,
              children: children,
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: DesignConstants.spacingMedium,
              children: children,
            ),
    );
  }
}
