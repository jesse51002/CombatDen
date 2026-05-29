import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_member_app_preview.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/theme_tab/edit_branding_dialog.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/theme_tab/theme_grid.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/theme_tab/theme_preview_pane.dart';
import 'package:app_management/features/members/presentation/widgets/themes_library/library_view.dart';
import 'package:theme_flutter/customization_runtime.dart';
import 'package:theme_flutter/showcase/showcase_screen.dart';
import 'package:theme_flutter/showcase/showcase_slots.dart';

// The tenant + preset the preview wears on first paint.
const String _kAppId = 'combatden';
const String _kSeedDesignId = 'ApexMMA';

enum _Mode { library, phone }

/// Theme tab — defaults to the **themes library** (filter + search +
/// grid). Tapping a theme card switches to the phone-frame preview;
/// the side pane's "Back to library" link returns. Engine init runs
/// once per mount and is shared across both modes.
class LiveThemePreviewTab extends StatefulWidget {
  const LiveThemePreviewTab({super.key});

  @override
  State<LiveThemePreviewTab> createState() => _LiveThemePreviewTabState();
}

class _LiveThemePreviewTabState extends State<LiveThemePreviewTab> {
  late final Future<void> _engineReady = ThemeRuntime.initialize(
    appId: _kAppId,
    designId: _kSeedDesignId,
    expectedColors: ShowcaseSlots.expectedColors,
    expectedImages: ShowcaseSlots.expectedImages,
    expectedFonts: ShowcaseSlots.expectedFonts,
    expectedText: ShowcaseSlots.expectedText,
    expectedIcons: ShowcaseSlots.expectedIcons,
    // Live preview: RAM-only image provider (no disk-cache litter on dev
    // reloads). A page reload re-fetches the config and content-hashed
    // `?v=` URLs pick up any asset edits.
    livePreview: true,
  );

  _Mode _mode = _Mode.library;

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

  void _openLibrary() => setState(() => _mode = _Mode.library);
  void _openPhone() => setState(() => _mode = _Mode.phone);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _engineReady,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _CenteredSpinner();
        }
        return switch (_mode) {
          _Mode.library => LibraryView(onPicked: _openPhone),
          _Mode.phone => _PhonePreview(
              slide: _slide,
              gymName: _gymName,
              gymLogo: _gymLogo,
              onPrev: _prevSlide,
              onNext: _nextSlide,
              onSelectSlide: _selectSlide,
              onEditBranding: _editBranding,
              onBackToLibrary: _openLibrary,
            ),
        };
      },
    );
  }
}

class _PhonePreview extends StatelessWidget {
  const _PhonePreview({
    required this.slide,
    required this.gymName,
    required this.gymLogo,
    required this.onPrev,
    required this.onNext,
    required this.onSelectSlide,
    required this.onEditBranding,
    required this.onBackToLibrary,
  });

  final int slide;
  final String gymName;
  final ImageProvider gymLogo;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<int> onSelectSlide;
  final VoidCallback onEditBranding;
  final VoidCallback onBackToLibrary;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        Expanded(
          child: ThemePreviewPane(
            engineReady: Future.value(),
            slide: slide,
            gymName: gymName,
            gymLogo: gymLogo,
            onPrev: onPrev,
            onNext: onNext,
            onSelect: onSelectSlide,
            onEditBranding: onEditBranding,
          ),
        ),
        SizedBox(
          width: 300,
          child: ThemeGrid(onBackToLibrary: onBackToLibrary),
        ),
      ],
    );
  }
}

class _CenteredSpinner extends StatelessWidget {
  const _CenteredSpinner();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        height: 32,
        width: 32,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: DesignConstants.primaryColor,
        ),
      ),
    );
  }
}
