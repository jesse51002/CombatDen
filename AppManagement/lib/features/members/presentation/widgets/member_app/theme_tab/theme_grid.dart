import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/theme_tab/theme_card.dart';
import 'package:app_management/shared/widgets/section_card.dart';
import 'package:customization_engine/customization_runtime.dart';
import 'package:customization_engine/data/models/customization_style.dart';

/// "App Theme" picker: a compact, independently-scrolling list of the
/// generated themes, the active one highlighted. It fills its column and
/// scrolls on its own, so scrolling the themes never moves the phone.
/// Tapping a card switches the live preview. Degrades quietly when the
/// service is down.
class ThemeGrid extends StatelessWidget {
  final Future<List<CustomizationStyle>> catalog;

  const ThemeGrid({super.key, required this.catalog});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text('App Theme', style: DesignConstants.h2),
        Expanded(
          child: FutureBuilder<List<CustomizationStyle>>(
            future: catalog,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const _CatalogMessage.loading();
              }
              if (snapshot.hasError) {
                return const _CatalogMessage(
                  'Could not reach the customization service. Start it and '
                  'reopen this tab to load the themes.',
                );
              }
              final styles = snapshot.data ?? const <CustomizationStyle>[];
              if (styles.isEmpty) {
                return const _CatalogMessage('No themes generated yet.');
              }
              return ListenableBuilder(
                listenable: CustomizationRuntime.changes,
                builder: (context, _) {
                  final active = CustomizationRuntime.activeDesignId;
                  return ListView.separated(
                    itemCount: styles.length,
                    // ListView.separated has no `spacing:`; the separator
                    // builder is the only way to gap its items, so SizedBox
                    // here is intentional, not a spacing-rule violation.
                    separatorBuilder: (_, _) => const SizedBox(
                      height: DesignConstants.spacingMedium,
                    ),
                    itemBuilder: (context, i) => ThemeCard(
                      style: styles[i],
                      isActive: styles[i].id == active,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CatalogMessage extends StatelessWidget {
  final String? message;

  const _CatalogMessage(this.message);
  const _CatalogMessage.loading() : message = null;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(
        child: message == null
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: DesignConstants.primaryColor,
                ),
              )
            : Text(
                message!,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}
