import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'stub_asset_bundle.dart';

import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/features/class_booking/data/class_info.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_layout_body.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_layout_data.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// The gym's classes, fixed so the schedule the generator derives from
/// them is identical on every run. Four of them, because the generator
/// rotates classes through four fixed time slots.
const List<ClassInfo> kTestClasses = [
  ClassInfo(
    name: 'Muay Thai',
    imageUrl: 'https://layout.test/muay-thai.jpg',
    description: 'Striking fundamentals.',
    instructorName: 'Andy Zerger',
    instructorBio: 'Head coach.',
    instructorImageUrl: 'https://layout.test/andy.jpg',
  ),
  ClassInfo(
    name: 'BJJ No-Gi',
    imageUrl: 'https://layout.test/bjj.jpg',
    description: 'Grappling without the gi.',
    instructorName: 'Renata Alves',
    instructorBio: 'Black belt.',
    instructorImageUrl: 'https://layout.test/renata.jpg',
  ),
  ClassInfo(
    name: 'Boxing Basics',
    imageUrl: 'https://layout.test/boxing.jpg',
    description: 'Footwork and the jab.',
    instructorName: 'Marcus Hale',
    instructorBio: 'Amateur champion.',
    instructorImageUrl: 'https://layout.test/marcus.jpg',
  ),
  ClassInfo(
    name: 'Wrestling',
    imageUrl: 'https://layout.test/wrestling.jpg',
    description: 'Takedowns and control.',
    instructorName: 'Dana Whitfield',
    instructorBio: 'Collegiate wrestler.',
    instructorImageUrl: 'https://layout.test/dana.jpg',
  ),
];

/// Pump at a real phone size. At the default 800x600 test surface a
/// cramped row still fits, so an arrangement that overflows on an actual
/// device would pass unnoticed.
void phoneSized(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// Home exactly as `HomeScreen` frames it — the screen scaffold and the
/// bottom nav around one page's body — with the format forced and the
/// data injected, so no repository, network or clock is involved.
///
/// [pushed] collects every route name the tree pushes, which is how the
/// gate proves a class row still opens class detail.
Widget homeHost({
  required HomeFormat format,
  required HomeLayoutData data,
  List<String>? pushed,
}) {
  return withStubAssets(
    MaterialApp(
      onGenerateRoute: (settings) {
        pushed?.add(settings.name ?? '');
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const SizedBox.shrink(),
        );
      },
      home: AppScreenScaffold(
        horizontalPadding: AppScreenHorizontalPadding.none,
        bottomNav: const AppBottomNavBar(selected: AppBottomNavTab.home),
        child: HomeLayoutBody(formatOverride: format, data: data),
      ),
    ),
  );
}
