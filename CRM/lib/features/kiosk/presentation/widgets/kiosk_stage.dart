import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The centered, max-width content stage every kiosk sub-screen sits in. It
/// scrolls when the content outgrows the viewport; [center] decides whether
/// shorter content sits centered (result screens) or top-aligned.
///
/// A [footer] is PINNED to the bottom of the fold while the content scrolls
/// beneath it — a way out a tall class grid can push below the fold is not a
/// way out. A [header] pins to the TOP for the same reason: whose plan /
/// waiver / card this is must not scroll away mid-step.
///
/// It is the kiosk's ONE stage, and both lanes sit in it: the check-in
/// screens mount it directly, and the signup's shared `FlowStepScaffold` is
/// handed it as its SHELL (see `KioskStepScaffold`). The shared component set
/// carries no stage of its own — a full-screen kiosk and a staff dialog are
/// exactly where the two surfaces part company.
class KioskStage extends StatelessWidget {
  final Widget child;
  final bool center;

  /// The escape foot on an in-progress flow. Ignores [center].
  final Widget? footer;

  /// The step rail, screen head, and "who is this for" strip.
  final Widget? header;

  /// Lay [child] out at the height that is LEFT rather than scrolling it: the
  /// step gets a BOUNDED box it may use `Expanded` inside, and owns its own
  /// overflow in exchange. Only for steps that scroll something internally.
  final bool fillBody;

  /// Drives the pinned-body scroll view so a step can return it to the top
  /// itself. Only honoured on the pinned header/footer path.
  final ScrollController? bodyScrollController;

  const KioskStage({
    super.key,
    required this.child,
    this.center = false,
    this.footer,
    this.header,
    this.fillBody = false,
    this.bodyScrollController,
  });

  @override
  Widget build(BuildContext context) {
    final foot = footer;
    final head = header;
    if (foot != null || head != null) {
      return _Railed(
        child: _Pinned(
          header: head,
          footer: foot,
          body: child,
          fill: fillBody,
          controller: bodyScrollController,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: _Railed(
              center: center,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// The stage's content rail: centered, capped at the content width, padded.
class _Railed extends StatelessWidget {
  final Widget child;
  final bool center;

  const _Railed({required this.child, this.center = false});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: center ? Alignment.center : Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: DesignConstants.navMaxWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignConstants.paddingBig,
            vertical: DesignConstants.paddingBig,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The body, between whichever bands are held on the fold. Header→content
/// takes the wider section gap; the footer rides tighter, since it carries its
/// own hairline.
class _Pinned extends StatelessWidget {
  final Widget body;
  final Widget? header;
  final Widget? footer;
  final bool fill;
  final ScrollController? controller;

  const _Pinned({
    required this.body,
    this.header,
    this.footer,
    this.fill = false,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final head = header;
    final foot = footer;
    final content = Expanded(
      child: fill
          ? body
          : SingleChildScrollView(controller: controller, child: body),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        if (head == null)
          content
        else
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingBig,
              children: [head, content],
            ),
          ),
        ?foot,
      ],
    );
  }
}
