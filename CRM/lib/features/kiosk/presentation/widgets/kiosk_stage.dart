import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The centered, max-width content stage every kiosk sub-screen sits in — a
/// centered column capped at a content width, on the kiosk ground. Scrolls
/// when the content is taller than the viewport so nothing is ever clipped on
/// a short iPad fold; otherwise [center] decides whether the content sits
/// centered (result screens) or top-aligned (home / class pick).
///
/// A [footer] is PINNED to the bottom of the fold while the content scrolls
/// beneath it. That is the whole point for the escape hatch: a way out that a
/// tall class grid can push below the fold is not a way out. A [header] is the
/// mirror of it, pinned to the TOP for the same reason: whose plan / whose
/// waiver / whose card this is must not scroll away mid-step. Without either
/// the stage keeps its plain scroll-the-whole-thing behaviour, so no existing
/// screen changes.
class KioskStage extends StatelessWidget {
  final Widget child;
  final bool center;

  /// Pinned to the bottom of the stage, inside the same content rail — the
  /// escape foot on an in-progress flow. Ignores [center] (a pinned foot has
  /// nothing to center against).
  final Widget? footer;

  /// Pinned to the TOP of the stage, inside the same content rail — the step
  /// rail, the screen head, and the "who is this for" strip.
  final Widget? header;

  /// Lay [child] out at the height that is LEFT rather than scrolling it.
  ///
  /// A step that opts in gets a BOUNDED box, so it may use `Expanded`
  /// internally and let its own panels scroll — which is how the waiver's
  /// reading box fills the fold instead of sitting at a borrowed height. The
  /// step is then responsible for its own overflow, so only steps that
  /// genuinely scroll something inside themselves should ask for it.
  final bool fillBody;

  const KioskStage({
    super.key,
    required this.child,
    this.center = false,
    this.footer,
    this.header,
    this.fillBody = false,
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

/// The body, between whichever bands are held on the fold.
///
/// The two gaps are deliberately different sizes: the header and the content
/// it heads are a title/content pair and take the section gap, while the
/// footer rides the tighter one it already carries its own hairline above.
class _Pinned extends StatelessWidget {
  final Widget body;
  final Widget? header;
  final Widget? footer;
  final bool fill;

  const _Pinned({
    required this.body,
    this.header,
    this.footer,
    this.fill = false,
  });

  @override
  Widget build(BuildContext context) {
    final head = header;
    final foot = footer;
    final content = Expanded(
      child: fill ? body : SingleChildScrollView(child: body),
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
