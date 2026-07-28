import 'package:flutter/material.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/class_layout_data.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_hero_scrim.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_keyed_banner.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_screen_topbar.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_sheet_surface.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_image_banner.dart';

/// Where the sheet's top edge sits, as a fraction of the body height.
const double _kOpenTop = 0.10;
const double _kRestTop = 0.44;

const Duration _kSnapDuration = Duration(milliseconds: 220);

/// `ClassFormat.detailSheet` — the photo is a fixed backdrop and the
/// content rises over it as a draggable sheet.
///
/// The reserve action sits at the top of the sheet: in thumb reach on
/// the way down, rather than at the end of a scroll. Hand-built from
/// [AnimatedPositioned] + a drag strip rather than
/// `DraggableScrollableSheet`, because that widget reserves the sheet's
/// [ScrollController] for its own drag plumbing and the capture harness
/// needs that slot ([ClassLayoutData.captureController]).
class ClassDetailSheet extends StatefulWidget {
  const ClassDetailSheet({super.key, required this.data});

  final ClassLayoutData data;

  @override
  State<ClassDetailSheet> createState() => _ClassDetailSheetState();
}

class _ClassDetailSheetState extends State<ClassDetailSheet> {
  double _top = _kRestTop;
  bool _dragging = false;

  void _onDragUpdate(DragUpdateDetails details, double height) {
    if (height <= 0) return;
    setState(() {
      _dragging = true;
      _top = (_top + details.delta.dy / height).clamp(_kOpenTop, _kRestTop);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final open = velocity == 0
        ? _top < (_kOpenTop + _kRestTop) / 2
        : velocity < 0;
    setState(() {
      _dragging = false;
      _top = open ? _kOpenTop : _kRestTop;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return Stack(
          children: [
            Positioned.fill(
              child: ClassKeyedBanner(
                data: widget.data,
                treatment: ClassBannerTreatment.backdrop,
              ),
            ),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ClassHeroScrim(),
            ),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ClassScreenTopbar(),
            ),
            AnimatedPositioned(
              duration: _dragging ? Duration.zero : _kSnapDuration,
              curve: Curves.easeOut,
              top: _top * height,
              left: 0,
              right: 0,
              bottom: 0,
              child: ClassSheetSurface(
                data: widget.data,
                onDragUpdate: (details) => _onDragUpdate(details, height),
                onDragEnd: _onDragEnd,
              ),
            ),
          ],
        );
      },
    );
  }
}
