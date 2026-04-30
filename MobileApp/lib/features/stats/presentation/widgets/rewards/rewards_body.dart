import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/rewards_carousel.dart';

/// Title + subtitle + swipeable, auto-advancing reward carousel + featured
/// caption (name, discount, points cost). Auto-advances 5 seconds after the
/// previous transition finishes; manual swipes reset the timer.
class RewardsBody extends StatefulWidget {
  const RewardsBody({super.key, required this.stats});

  final MockRewardsStats stats;

  @override
  State<RewardsBody> createState() => _RewardsBodyState();
}

class _RewardsBodyState extends State<RewardsBody> {
  static const _idleDelay = Duration(seconds: 5);
  static const _slideDuration = Duration(milliseconds: 450);

  // Large offset lets the user swipe backward "forever" without hitting
  // page 0. The actual item shown is `_page % items.length`.
  static const _initialPageBase = 10000;

  late final PageController _controller;
  late int _page = _initialPageBase -
      (_initialPageBase % widget.stats.items.length) +
      widget.stats.featuredIndex;
  late int _index = _page % widget.stats.items.length;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = PageController(
      initialPage: _page,
      viewportFraction: 0.45,
    );
    _scheduleNext();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer(_idleDelay, _advance);
  }

  Future<void> _advance() async {
    if (!mounted) return;
    await _controller.animateToPage(
      _page + 1,
      duration: _slideDuration,
      curve: Curves.easeInOutCubic,
    );
    if (!mounted) return;
    _scheduleNext();
  }

  void _onPageChanged(int page) {
    setState(() {
      _page = page;
      _index = page % widget.stats.items.length;
    });
    _scheduleNext();
  }

  @override
  Widget build(BuildContext context) {
    final featured = widget.stats.items[_index];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            Text(
              widget.stats.title,
              textAlign: TextAlign.center,
              style: DesignConstants.big2,
            ),
            Text(
              widget.stats.subtitle,
              textAlign: TextAlign.center,
              style: DesignConstants.pBig.copyWith(
                color: DesignConstants.text3rd,
              ),
            ),
          ],
        ),
        RewardsCarousel(
          items: widget.stats.items,
          controller: _controller,
          onPageChanged: _onPageChanged,
        ),
        AnimatedSwitcher(
          duration: _slideDuration,
          child: Column(
            key: ValueKey(_index),
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingMedium,
            children: [
              Text(
                featured.name,
                textAlign: TextAlign.center,
                style: DesignConstants.h1,
              ),
              Text(
                featured.discountLabel,
                textAlign: TextAlign.center,
                style: DesignConstants.h1Regular.copyWith(
                  color: DesignConstants.text3rd,
                ),
              ),
              Text(
                '${_formatPoints(featured.pointsCost)} pts',
                textAlign: TextAlign.center,
                style: DesignConstants.h1.copyWith(
                  color: DesignConstants.primaryColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _formatPoints(int n) {
  if (n < 1000) return '$n';
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
