import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

class ClassScheduleTitle extends StatelessWidget {
  const ClassScheduleTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('Class Schedule', style: DesignConstants.h2),
    );
  }
}
