import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/features/home/data/mock_class_schedule.dart';

/// The tap target every class row carries, defined once.
///
/// Each [ClassItemLayout] wraps its own arrangement in this, so no
/// layout can accidentally ship a row that does not open class detail.
class ClassItemTap extends StatelessWidget {
  const ClassItemTap({
    super.key,
    required this.classData,
    required this.child,
  });

  final MockClass classData;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pushNamed(
        AppRoutes.classDetail,
        arguments: classData,
      ),
      child: child,
    );
  }
}
