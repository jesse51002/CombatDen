import 'package:flutter/widgets.dart';

/// The assembled bands of one flow step, handed to the HOST so the host's own
/// shell places them.
///
/// The shell is the one piece of a step the two surfaces genuinely do not
/// share: the kiosk runs full-screen on a front-desk iPad (`KioskStage`) and
/// the desk runs inside an `AppDialog`. So `FlowStepScaffold` assembles the
/// rail + head + identity into [header], the step's content into [body] and
/// the foot into [footer], and stops there — a second stage of its own would be
/// a copy of whichever host it was written against.
class FlowShellParts {
  /// The PINNED top band: the step rail, the screen head, and the "who is this
  /// for" strip. A shell that lets it scroll away is a shell that lets the
  /// wrong plan be bought for the wrong child.
  final Widget header;

  /// The step's own content, between the pinned bands.
  final Widget body;

  /// The PINNED foot. A way out a tall grid can push below the fold is not a
  /// way out.
  final Widget footer;

  /// Lay [body] out at the height that is LEFT rather than scrolling it: the
  /// step gets a BOUNDED box it may use `Expanded` inside, and owns its own
  /// overflow in exchange. Only for steps that scroll something internally.
  final bool fillBody;

  /// Drives the scrolling body so a step can return it to the top itself — the
  /// plan step scrolls back up when the person changes.
  final ScrollController? bodyController;

  const FlowShellParts({
    required this.header,
    required this.body,
    required this.footer,
    this.fillBody = false,
    this.bodyController,
  });
}

/// How a host turns the assembled [FlowShellParts] into its own screen.
typedef FlowShellBuilder = Widget Function(
  BuildContext context,
  FlowShellParts parts,
);
