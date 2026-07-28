import 'package:flutter/material.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/class_layout_data.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_reserve_footer.dart';

/// The screen's single reserve action, with the capture harness's
/// reserve key already attached.
///
/// Every layout commits through this part exactly once. Rendering it
/// twice "for convenience" would change the screen's contract — one
/// commit point — rather than its arrangement, and
/// `test/class_invariants_test.dart` fails if a layout tries.
class ClassKeyedReserve extends StatelessWidget {
  const ClassKeyedReserve({
    super.key,
    required this.data,
    this.position = ClassReservePosition.pinned,
  });

  final ClassLayoutData data;
  final ClassReservePosition position;

  @override
  Widget build(BuildContext context) {
    return ClassReserveFooter(
      buttonKey: data.reserveKey,
      onReserve: data.onReserve,
      position: position,
    );
  }
}
