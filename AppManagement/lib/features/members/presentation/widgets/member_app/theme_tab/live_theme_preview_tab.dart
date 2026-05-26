import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_member_app_preview.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/theme_tab/edit_branding_dialog.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/theme_tab/theme_grid.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/theme_tab/theme_preview_pane.dart';
import 'package:customization_engine/customization_runtime.dart';
import 'package:customization_engine/data/models/customization_style.dart';
import 'package:customization_engine/showcase/showcase_screen.dart';
import 'package:customization_engine/showcase/showcase_slots.dart';

// The tenant + preset the preview wears on first paint.
const String _kAppId = 'combatden';
const String _kSeedDesignId = 'ApexMMA';

/// Theme tab: a large live phone preview on the left and a compact,
/// independently-scrolling theme picker on the right. Picking a theme
/// re-themes the phone instantly; the arrows / view chips under the phone
/// page through the showcase screens. The gym name + logo are the host's
/// own identity (from [kMockMemberAppPreview]) and are passed into the
/// preview as arguments — they are NOT a customization slot.
class LiveThemePreviewTab extends StatefulWidget {
  const LiveThemePreviewTab({super.key});

  @override
  State<LiveThemePreviewTab> createState() => _LiveThemePreviewTabState();
}

class _LiveThemePreviewTabState extends State<LiveThemePreviewTab> {
  late final Future<void> _engineReady = CustomizationRuntime.initialize(
    appId: _kAppId,
    designId: _kSeedDesignId,
    expectedColors: ShowcaseSlots.expectedColors,
    expectedImages: ShowcaseSlots.expectedImages,
    expectedFonts: ShowcaseSlots.expectedFonts,
    expectedText: ShowcaseSlots.expectedText,
    expectedIcons: ShowcaseSlots.expectedIcons,
    expectedLotties: ShowcaseSlots.expectedLotties,
  );

  late final Future<List<CustomizationStyle>> _catalog = _engineReady.then(
    (_) => CustomizationRuntime.fetchStyles(),
  );

  // Gym identity, owned by the host (seeded from the shared mock). The Edit
  // button under the phone updates the name; the logo is the in-memory asset.
  String _gymName = kMockMemberAppPreview.gymName;
  final ImageProvider _gymLogo = AssetImage(
    kMockMemberAppPreview.gymLogoAsset,
  );

  int _slide = 0;
  int get _count => ShowcaseScreen.values.length;

  void _nextSlide() => setState(() => _slide = (_slide + 1) % _count);
  void _prevSlide() =>
      setState(() => _slide = (_slide - 1 + _count) % _count);
  void _selectSlide(int i) => setState(() => _slide = i);

  Future<void> _editBranding() async {
    final name = await showEditBrandingDialog(context, _gymName);
    if (name != null && name.trim().isNotEmpty) {
      setState(() => _gymName = name.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        // Phone takes all the room it can; the theme picker is a fixed,
        // narrow column so its compact cards don't stretch into dead space.
        Expanded(
          child: ThemePreviewPane(
            engineReady: _engineReady,
            slide: _slide,
            gymName: _gymName,
            gymLogo: _gymLogo,
            onPrev: _prevSlide,
            onNext: _nextSlide,
            onSelect: _selectSlide,
            onEditBranding: _editBranding,
          ),
        ),
        SizedBox(
          width: 300,
          child: ThemeGrid(catalog: _catalog),
        ),
      ],
    );
  }
}
