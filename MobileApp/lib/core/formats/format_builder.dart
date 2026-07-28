import 'package:flutter/widgets.dart';

import 'package:mobile_app/core/formats/format_store.dart';

/// Rebuilds [builder] whenever the dev picker changes a format.
///
/// Wrap the point where a widget switches on a format — not the whole
/// app. Rebuilding locally is what lets a format change take effect
/// without re-keying the tree, which would reset the Navigator and drop
/// you back on Home mid-review.
class FormatBuilder extends StatelessWidget {
  const FormatBuilder({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FormatStore.instance,
      builder: (context, _) => builder(context),
    );
  }
}
