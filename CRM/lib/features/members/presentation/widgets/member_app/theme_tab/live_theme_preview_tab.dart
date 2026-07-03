import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/members/data/mock_member_app_preview.dart';
import 'package:crm/features/members/presentation/widgets/member_app/theme_tab/theme_grid.dart';
import 'package:crm/features/members/presentation/widgets/member_app/theme_tab/theme_preview_pane.dart';
import 'package:crm/features/members/presentation/widgets/themes_library/library_view.dart';
import 'package:crm/features/settings/presentation/dialogs/gym_profile_dialog.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:theme_flutter/customization_runtime.dart';
import 'package:crm/showcase/showcase_screen.dart';
import 'package:crm/showcase/showcase_slots.dart';

// The tenant the engine initializes on. NO gym is pre-selected — the member-app
// content surfaces stay empty until the admin picks one.
const String _kAppId = 'combatden';
// Last-resort seed when neither the URL nor the gym's saved theme supplies one
// (e.g. the public standalone browser, or an admin gym with no theme yet), only
// so the customization runtime has something to fetch on first paint.
const String _kSeedDesignId = 'ApexMMA';

// Below this preview width the phone goes full-bleed (mobile): no side-by-side
// theme list and no horizontal layout — just the phone with its own
// back-to-library button. At or above it, the phone sits beside the scrollable
// theme picker (the side pane that carries its own back link).
const double _kSideBySideMinWidth = 700;
const double _kSidePaneWidth = 300;

enum _Mode { library, phone }

/// Theme tab — defaults to the **themes library** (filter + search +
/// grid). Tapping a theme card switches to the phone-frame preview;
/// the side pane's "Back to library" link returns. Engine init runs
/// once per mount and is shared across both modes.
///
/// This widget is the reusable theme-browser **module**: the admin member-app
/// preview embeds it (default [routePath]), and the standalone theme-browser
/// build target (`lib/main_theme_browser.dart`) mounts it full-screen. The only
/// host-specific knob is [routePath] — the URL path the previewed theme is
/// mirrored onto (see [_syncUrl]).
class LiveThemePreviewTab extends StatefulWidget {
  /// The URL path the current preview state is mirrored onto as `?theme=…`.
  /// Defaults to the admin preview route so the embedded tab is unchanged; the
  /// standalone deploy passes [AppRoutes.home] for clean root deep links.
  final String routePath;

  const LiveThemePreviewTab({
    super.key,
    this.routePath = AppRoutes.memberAppPreview,
  });

  @override
  State<LiveThemePreviewTab> createState() => _LiveThemePreviewTabState();
}

class _LiveThemePreviewTabState extends State<LiveThemePreviewTab> {
  // The theme deep-linked in the URL (`…/app-preview?theme=…`), if any. On a
  // reload while previewing, this restores the phone view on that theme
  // instead of dropping back to the library.
  late final String? _urlTheme = _themeFromUrl();

  late final Future<void> _engineReady = _bootstrap();

  late _Mode _mode = _urlTheme != null ? _Mode.phone : _Mode.library;

  // Held once the engine is up so `dispose` can detach without re-resolving
  // `ThemeRuntime.changes`, which throws until `ThemeService` is registered.
  Listenable? _themeChanges;

  // Seed the engine on the intended theme — the deep-linked one, else the gym's
  // saved design — so it paints right the first time; `selectDesign` corrects an
  // in-session re-entry where the engine is already up. Both are no-throw and
  // fall back to bundled defaults.
  Future<void> _bootstrap() async {
    // The gym's persisted design (admin) or the deep-linked theme (either
    // target) is what the engine should boot on; the standalone browser and an
    // admin gym with no saved theme fall through to the constant seed.
    final intended = _urlTheme ?? selectedGym.savedThemeDesignId;
    await ThemeRuntime.initialize(
      appId: _kAppId,
      designId: intended ?? _kSeedDesignId,
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
    if (intended != null && ThemeRuntime.activeDesignId != intended) {
      await ThemeRuntime.selectDesign(intended);
    }
    // No gym is content-seeded here — the theme selection is decoupled from the
    // content gym. A seeded/deep-linked theme (phone view on reload) is resolved
    // to its showcase category by the side-pane's `reconcileFromCatalog` once
    // the catalog loads.
    if (!mounted) return;
    // Engine registered now — safe to listen and to mirror the current state
    // into the URL. The listener keeps the URL in step on every later
    // `selectDesign` (from the library grid or the side pane).
    _themeChanges = ThemeRuntime.changes..addListener(_syncUrl);
    _syncUrl();
  }

  @override
  void dispose() {
    _themeChanges?.removeListener(_syncUrl);
    super.dispose();
  }

  // Reads `?theme=…`, tolerating either URL strategy: hash (the route + query
  // live in the fragment) or path (a real query string).
  static String? _themeFromUrl() {
    String? clean(String? v) => (v != null && v.isNotEmpty) ? v : null;
    final fragment = Uri.base.fragment;
    if (fragment.isNotEmpty) {
      final fromHash = clean(Uri.tryParse(fragment)?.queryParameters['theme']);
      if (fromHash != null) return fromHash;
    }
    return clean(Uri.base.queryParameters['theme']);
  }

  // Mirror the current view into the address bar (replace, not push, so
  // theme-hopping doesn't stack history entries). Only the phone view carries
  // a theme; the library clears it.
  void _syncUrl() {
    if (!mounted) return;
    final theme =
        _mode == _Mode.phone ? ThemeRuntime.activeDesignId : null;
    final uri = Uri(
      path: widget.routePath,
      queryParameters: (theme == null || theme.isEmpty)
          ? null
          : <String, String>{'theme': theme},
    );
    SystemNavigator.routeInformationUpdated(uri: uri, replace: true);
  }

  int _slide = 0;
  bool _forward = true;
  int get _count => ShowcaseScreen.values.length;

  void _nextSlide() => setState(() {
        _forward = true;
        _slide = (_slide + 1) % _count;
      });
  void _prevSlide() => setState(() {
        _forward = false;
        _slide = (_slide - 1 + _count) % _count;
      });
  void _selectSlide(int i) => setState(() {
        _forward = i >= _slide;
        _slide = i;
      });

  void _openLibrary() {
    setState(() => _mode = _Mode.library);
    _syncUrl();
  }

  void _openPhone() {
    setState(() => _mode = _Mode.phone);
    _syncUrl();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _engineReady,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _CenteredSpinner();
        }
        // Rebuild on gym changes so the preview reflects a just-saved name /
        // logo and the admin gate flips correctly.
        return ListenableBuilder(
          listenable: selectedGym,
          builder: (context, _) {
            final isAdmin = selectedGym.gymId != null;
            // Admin: ALWAYS the real gym identity — the mock name exists
            // only for the public browser (no gym there). The logo is NEVER
            // a bundled asset here: the gym's uploaded logo when set, else
            // null — the showcase topbar then falls through to the ACTIVE
            // THEME's logo (themeTabPreview resolution order in
            // showcase_topbar.dart), so switching themes re-logos the mock.
            final gymName = isAdmin
                ? (selectedGym.gymName ?? '')
                : kMockMemberAppPreview.gymName;
            final ImageProvider? gymLogo =
                isAdmin && (selectedGym.logoUrl?.isNotEmpty ?? false)
                    ? NetworkImage(selectedGym.logoUrl!)
                    : null;

            // The Gym profile editor is ADMIN-ONLY: the phone preview's
            // "Edit gym name / logo" button (under the mock) opens
            // [GymProfileDialog]. The public standalone browser has no gym
            // (gymId null) and no Supabase, so the button never renders and
            // the dialog's bloc is never constructed there.
            return switch (_mode) {
              _Mode.library => LibraryView(onPicked: _openPhone),
              _Mode.phone => _PhonePreview(
                  engineReady: _engineReady,
                  slide: _slide,
                  forward: _forward,
                  gymName: gymName,
                  gymLogo: gymLogo,
                  onPrev: _prevSlide,
                  onNext: _nextSlide,
                  onSelectSlide: _selectSlide,
                  onBackToLibrary: _openLibrary,
                  onEditBranding: isAdmin
                      ? () => GymProfileDialog.show(context)
                      : null,
                ),
            };
          },
        );
      },
    );
  }
}

class _PhonePreview extends StatelessWidget {
  const _PhonePreview({
    required this.engineReady,
    required this.slide,
    required this.forward,
    required this.gymName,
    required this.gymLogo,
    required this.onPrev,
    required this.onNext,
    required this.onSelectSlide,
    required this.onBackToLibrary,
    this.onEditBranding,
  });

  final Future<void> engineReady;
  final int slide;
  final bool forward;
  final String gymName;
  final ImageProvider? gymLogo;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<int> onSelectSlide;
  final VoidCallback onBackToLibrary;
  final VoidCallback? onEditBranding;

  @override
  Widget build(BuildContext context) {
    final pane = ThemePreviewPane(
      engineReady: engineReady,
      slide: slide,
      forward: forward,
      gymName: gymName,
      gymLogo: gymLogo,
      onPrev: onPrev,
      onNext: onNext,
      onSelect: onSelectSlide,
      onEditBranding: onEditBranding,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Mobile / narrow: the phone is the whole thing — no side list, no
        // horizontal layout. The side pane's back link is gone, so the phone
        // gets its own back-to-library button stacked above it.
        if (constraints.maxWidth < _kSideBySideMinWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingLarge,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: AppOutlineButton(
                  text: '← Back to library',
                  onPressed: onBackToLibrary,
                ),
              ),
              Expanded(child: pane),
            ],
          );
        }
        // Wide: phone preview beside the scrollable theme picker.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingBig,
          children: [
            Expanded(child: pane),
            SizedBox(
              width: _kSidePaneWidth,
              child: ThemeGrid(onBackToLibrary: onBackToLibrary),
            ),
          ],
        );
      },
    );
  }
}

class _CenteredSpinner extends StatelessWidget {
  const _CenteredSpinner();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        height: DesignConstants.spinnerSizeLarge,
        width: DesignConstants.spinnerSizeLarge,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: DesignConstants.primaryColor,
        ),
      ),
    );
  }
}
