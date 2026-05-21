import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/customization/customization_runtime.dart';
import 'package:mobile_app/customization/data/models/customization_style.dart';
import 'package:mobile_app/features/style_select/presentation/widgets/style_list/style_list.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// Reached by double-tapping the home logo. Lists the app's styles
/// (design name + celebration image) fetched from the
/// CustomizationService; tapping one switches the live theme and pops
/// back to the now-re-themed app.
class StyleSelectScreen extends StatefulWidget {
  const StyleSelectScreen({super.key});

  @override
  State<StyleSelectScreen> createState() => _StyleSelectScreenState();
}

class _StyleSelectScreenState extends State<StyleSelectScreen> {
  late final Future<List<CustomizationStyle>> _stylesFuture =
      CustomizationRuntime.fetchStyles();
  bool _busy = false;

  Future<void> _select(CustomizationStyle style) async {
    if (_busy) return;
    setState(() => _busy = true);
    await CustomizationRuntime.selectDesign(style.id);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingBig,
          children: [
            const _StyleSelectHeader(),
            FutureBuilder<List<CustomizationStyle>>(
              future: _stylesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const _StyleStatus(message: 'Loading styles…');
                }
                final styles = snapshot.data ?? const [];
                if (snapshot.hasError || styles.isEmpty) {
                  return const _StyleStatus(
                    message: 'No styles available right now.',
                  );
                }
                return StyleList(
                  styles: styles,
                  activeId: CustomizationRuntime.activeDesignId,
                  onSelect: _select,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Back chevron + screen title.
class _StyleSelectHeader extends StatelessWidget {
  const _StyleSelectHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: Icon(
            Symbols.chevron_left_sharp,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.text,
            size: DesignConstants.iconSize2xl,
          ),
        ),
        Expanded(
          child: Text('Choose a style', style: DesignConstants.h1),
        ),
      ],
    );
  }
}

/// Centered loading / empty / error message.
class _StyleStatus extends StatelessWidget {
  const _StyleStatus({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: DesignConstants.spacingBig),
      child: Center(
        child: Text(
          message,
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
