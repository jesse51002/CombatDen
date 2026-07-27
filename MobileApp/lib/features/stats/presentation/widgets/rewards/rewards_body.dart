import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_app/features/stats/data/rewards_card_view.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/rewards_card_layout.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/rewards_giftbox_intro.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';

/// Giftbox intro animation, then the card itself: the intro gate, the
/// auto-advance timer, and the carousel's page state. Everything the card
/// LOOKS like is decided by [RewardsCardView] and drawn by
/// [RewardsCardLayout].
class RewardsBody extends StatefulWidget {
  const RewardsBody({
    super.key,
    required this.view,
    this.controller,
  });

  final RewardsCardView view;
  final PostClassController? controller;

  @override
  State<RewardsBody> createState() => _RewardsBodyState();
}

class _RewardsBodyState extends State<RewardsBody> {
  static const _idleDelay = Duration(seconds: 5);
  static const _slideDuration = Duration(milliseconds: 450);

  // Large offset lets the user swipe backward "forever" without hitting
  // page 0. The actual item shown is `_page % slides.length`.
  static const _initialPageBase = 10000;

  late final PageController _controller;
  late final int _count = widget.view.slides.length;
  late int _page = _count <= 0
      ? _initialPageBase
      : _initialPageBase -
          (_initialPageBase % _count) +
          widget.view.featuredIndex.clamp(0, _count - 1);
  late int _index = _count <= 0 ? 0 : _page % _count;
  Timer? _timer;
  bool _showCarousel = false;

  @override
  void initState() {
    super.initState();
    // Not on the constructor: it stays `const`, and a const assert can't read
    // a field off a parameter. `build` carries the release-mode guard.
    assert(
      widget.view.slides.isNotEmpty,
      'RewardsBody needs at least one slide — the screen falls back to the '
      'bundled catalog rather than handing over an empty list.',
    );
    _controller = PageController(
      initialPage: _page,
      viewportFraction: 0.45,
    );
    widget.controller?.registerSkipHandler(_skipToFinal);
  }

  @override
  void dispose() {
    widget.controller?.clearSkipHandler();
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _skipToFinal() {
    if (_showCarousel) return;
    setState(() => _showCarousel = true);
    _scheduleNext();
    widget.controller?.markDone();
  }

  void _onIntroDone() {
    if (!mounted) return;
    setState(() => _showCarousel = true);
    _scheduleNext();
    widget.controller?.markDone();
  }

  void _scheduleNext() {
    _timer?.cancel();
    // One reward is the whole catalog: advancing would animate a 450ms slide
    // from a photo to the identical photo, with no caption cross-fade and no
    // pulse — an unexplained drift. There is nowhere to go, so don't go.
    if (_count <= 1) return;
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
      _index = _count <= 0 ? 0 : page % _count;
    });
    _scheduleNext();
  }

  @override
  Widget build(BuildContext context) {
    // Today's screen can never hand over an empty list, but this is a public
    // widget and `_initialPageBase % 0` would throw.
    if (widget.view.slides.isEmpty) return const SizedBox.shrink();
    if (!_showCarousel) {
      return SizedBox.expand(
        child: GiftboxIntro(onComplete: _onIntroDone),
      );
    }
    return RewardsCardLayout(
      view: widget.view,
      controller: _controller,
      featuredIndex: _index,
      onPageChanged: _onPageChanged,
      slideDuration: _slideDuration,
    );
  }
}
