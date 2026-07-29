import 'package:flutter/material.dart';
import 'package:mobile_app/core/formats/format_builder.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/core/formats/theme_layout.dart';
import 'package:mobile_app/features/videos/presentation/layouts/videos_carousel_rows.dart';
import 'package:mobile_app/features/videos/presentation/layouts/videos_editorial_stack.dart';
import 'package:mobile_app/features/videos/presentation/layouts/videos_layout_data.dart';
import 'package:mobile_app/features/videos/presentation/layouts/videos_mosaic.dart';
import 'package:mobile_app/features/videos/presentation/layouts/videos_shorts_column.dart';
import 'package:mobile_app/features/videos/presentation/layouts/videos_tag_rail.dart';

/// The feed area below the topbar on `VideosScreen`: the top-filter
/// pills, the featured hero, and one section per tag.
///
/// Resolves the tenant's `videos_format` slot and delegates to one of
/// the layouts in `presentation/layouts/`, each of which arranges the
/// SAME [VideosLayoutData]. A layout may move these and change their
/// prominence. It may not drop one, add one, or reach past the payload
/// for data of its own — `test/videos_invariants_test.dart` is the
/// gate that proves it.
///
/// Returns a **sliver**: the screen owns one scroll for topbar and
/// feed together, and a format that pins its filter (or its rail) needs
/// to say so in the same sliver list.
class VideosFeedBody extends StatelessWidget {
  const VideosFeedBody({
    super.key,
    required this.data,
    this.formatOverride,
  });

  final VideosLayoutData data;

  /// Forces a layout instead of resolving it from the customization.
  /// Used by the layout-invariant tests and the format preview; null in
  /// normal app use.
  final VideosFormat? formatOverride;

  @override
  Widget build(BuildContext context) {
    return FormatBuilder(builder: _build);
  }

  Widget _build(BuildContext context) {
    return switch (formatOverride ?? ThemeLayout.videos()) {
      VideosFormat.carouselRows => VideosCarouselRows(data: data),
      VideosFormat.editorialStack => VideosEditorialStack(data: data),
      VideosFormat.mosaic => VideosMosaic(data: data),
      VideosFormat.shortsColumn => VideosShortsColumn(data: data),
      VideosFormat.tagRail => VideosTagRail(data: data),
    };
  }
}
