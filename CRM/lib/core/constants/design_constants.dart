import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:crm/core/state/theme_controller.dart';

/// The CRM's design system — one source of truth for every color, type style,
/// spacing, radius, and elevation token.
///
/// **Light + dark.** Color, gradient, shadow, and text-style tokens are
/// *getters* that resolve through [themeController.isDark], so a single
/// theme-mode change re-skins the whole app — every widget reads
/// `DesignConstants.<token>` directly (the app never uses `Theme.of(context)`),
/// and `main.dart` wraps `MaterialApp` in a `ListenableBuilder` on
/// [themeController] so the tree repaints when the palette flips. The two
/// palettes sit side by side below as private `_l*` (light) / `_d*` (dark)
/// constants. Spacing, radius, icon sizes, nav dims, and the fonts are
/// theme-independent and stay `const` / `final`.
///
/// **The look.** Light is "The Daylit Control Desk" — landing-aligned, cool
/// off-white ground, white lifted cards, one sapphire accent (see `DESIGN.md`).
/// Dark is its night shift: the same Restrained system inverted onto a cool
/// charcoal ground (not navy), surfaces lift by getting *lighter*, hairlines
/// flip light-on-dark, the accent lightens, and status hues brighten. Both keep
/// the One Light Rule (sapphire ≤10%) and the Cool-Tinted Rule (no `#000`/`#fff`).
class DesignConstants {
  static bool get _dark => themeController.isDark;

  // ── Light palette (the daylit control desk) ──
  static const Color _lPrimary = Color(0xFF2A67BD);
  static const Color _lAccentDark = Color(0xFF1F5099);
  static const Color _lAccentSoft = Color(0xFFE8F0FB);
  static const Color _lDarkPrimary = Color(0xFF274777);
  static const Color _lHyperlink = _lAccentDark;
  static const Color _lBackground = Color(0xFFF3F5F8);
  static const Color _lBackgroundAlt = Color(0xFFEEF1F6);
  static const Color _lSurface = Color(0xFFFFFFFF);
  static const Color _lText = Color(0xFF16181D);
  static const Color _lText2nd = Color(0xFF565B66);
  static const Color _lText3rd = Color(0xFF878D99);
  static const Color _lLine = Color.fromARGB(23, 20, 22, 30);
  static const Color _lLineSoft = Color.fromARGB(15, 20, 22, 30);
  static const Color _lGoodGreen = Color(0xFF1D7D3E);
  static const Color _lOkYellow = Color(0xFF915C08);
  static const Color _lBadRed = Color(0xFFB6322D);

  // ── Dark palette (the night shift) ──
  static const Color _dPrimary = Color(0xFF3E7CD6);
  static const Color _dAccentDark = Color(0xFF2F62B5);
  static const Color _dAccentSoft = Color(0xFF1C2840);
  static const Color _dDarkPrimary = Color(0xFF36527E);
  static const Color _dHyperlink = Color(0xFF5A93E6);
  static const Color _dBackground = Color(0xFF14161B);
  static const Color _dBackgroundAlt = Color(0xFF191C22);
  static const Color _dSurface = Color(0xFF1E212A);
  static const Color _dPopup = Color(0xFF242833);
  static const Color _dText = Color(0xFFE9ECF2);
  static const Color _dText2nd = Color(0xFFA6ACB8);
  static const Color _dText3rd = Color(0xFF828B98);
  // Hairlines flip to a cool off-white at low alpha on the dark ground.
  static const Color _dLine = Color.fromARGB(31, 233, 236, 242);
  static const Color _dLineSoft = Color.fromARGB(18, 233, 236, 242);
  static const Color _dGoodGreen = Color(0xFF3FB46A);
  static const Color _dOkYellow = Color(0xFFDBA13F);
  static const Color _dBadRed = Color(0xFFE26C64);
  // A dark-mode purple base for the purple status tint (no light counterpart
  // token — the light tint derives from its own muted base below).
  static const Color _dPurpleTint = Color(0xFF8A7CC0);

  // ── Accent — the single brand blue + its gradient partner. ──
  static Color get primaryColor => _dark ? _dPrimary : _lPrimary;
  static Color get accentDark => _dark ? _dAccentDark : _lAccentDark;
  static Color get accentSoft => _dark ? _dAccentSoft : _lAccentSoft;
  static Color get primaryColor50 => primaryColor.withValues(alpha: 0.5);
  static Color get primaryColor25 => primaryColor.withValues(alpha: 0.25);
  static Color get primaryColor10 => primaryColor.withValues(alpha: 0.1);

  // The label color that sits on a sapphire / gradient fill — near-white in
  // both themes (white on light, the near-white ink on dark), so a filled
  // accent (primary button, selected pill) always carries a legible label.
  // Safe only on a fill that is dark in BOTH themes (the gradient, the
  // saturated reds/greens). For a fill whose luminance flips between themes,
  // use [onFill] instead.
  static Color get onAccent => _dark ? _dText : _lSurface;

  // The legible label/icon color for an arbitrary SOLID colored fill, chosen
  // by the fill's luminance: near-white [onAccent] on a dark fill, near-black
  // ink on a light one. Needed because some fills flip brightness between
  // themes — e.g. `okYellow` is a dark amber in light mode (wants a light
  // label) but a bright gold in dark mode (wants a dark label) — so a single
  // fixed token can't stay legible on both.
  static Color onFill(Color fill) =>
      ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
          // Near-white, same as an accent label on a dark fill.
          ? onAccent
          // Always the dark ink: a light fill needs dark text in EITHER theme,
          // so this is intentionally the fixed light-theme ink (`_lText`), not
          // `_dText` or a theme-aware token — don't "fix" it to one.
          : _lText;

  static Color get darkPrimary => _dark ? _dDarkPrimary : _lDarkPrimary;

  // Top-to-bottom gradient for primary actions (landing GWButton primary).
  static LinearGradient get primaryGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [primaryColor, accentDark],
      );

  // ── Ground / surfaces / ink ramp. ──
  static Color get backgroundColor => _dark ? _dBackground : _lBackground;
  static Color get backgroundAlt => _dark ? _dBackgroundAlt : _lBackgroundAlt;
  static Color get surface => _dark ? _dSurface : _lSurface;

  static Color get text => _dark ? _dText : _lText;
  static Color get text2nd => _dark ? _dText2nd : _lText2nd;
  static Color get text3rd => _dark ? _dText3rd : _lText3rd;

  // Cards are the surface color; in light they lift to white off the ground,
  // in dark they lift by being a step lighter than the ground.
  static Color get card => surface;
  // Hairline border / divider — decoupled from `card` (a card with a card-color
  // divider would be invisible).
  static Color get line => _dark ? _dLine : _lLine;
  // Softer hairline — e.g. the mobile menu's link separators.
  static Color get lineSoft => _dark ? _dLineSoft : _lLineSoft;
  static Color get divider => line;

  // Transient surfaces (menus / dialogs) lift most. Light tints the surface a
  // hair toward ink; dark steps up to the lightest neutral.
  static Color get popup => _dark
      ? _dPopup
      : Color.alphaBlend(_lText.withValues(alpha: 0.04), _lSurface);

  // Preview phone mockup (PhoneFrame) device body — deliberately NOT on the ink
  // ramp. Keying it off `text` would flip the phone to near-white in dark; a
  // device should read as a real phone. Black on the light panel, graphite (a
  // step lighter than the dark panel) on the dark panel so it stays visible
  // without going white. Its shadow stays dark in both themes.
  static Color get deviceBody => _dark ? const Color(0xFF2E323C) : _lText;
  static Color get deviceShadow => _dark
      ? const Color(0x80000000)
      : _lText.withValues(alpha: 0.25);

  static Color get hyperlink => _dark ? _dHyperlink : _lHyperlink;
  static Color get goodGreen => _dark ? _dGoodGreen : _lGoodGreen;
  static Color get okYellow => _dark ? _dOkYellow : _lOkYellow;
  static Color get badRed => _dark ? _dBadRed : _lBadRed;

  // Tinted status backgrounds (cell / chip washes). Light uses muted dark bases
  // at 25%; dark uses the brightened status hue at ~18% over the dark ground.
  static Color get yellowDark => _dark
      ? _dOkYellow.withValues(alpha: 0.18)
      : const Color(0xFF6D5B35).withValues(alpha: 0.25);
  static Color get greenDark => _dark
      ? _dGoodGreen.withValues(alpha: 0.18)
      : const Color(0xFF395F47).withValues(alpha: 0.25);
  static Color get purpleDark => _dark
      ? _dPurpleTint.withValues(alpha: 0.18)
      : const Color(0xFF5A4E72).withValues(alpha: 0.25);
  static Color get blueDark => _dark
      ? _dPrimary.withValues(alpha: 0.18)
      : const Color(0xFF405677).withValues(alpha: 0.25);
  static Color get redDark => _dark
      ? _dBadRed.withValues(alpha: 0.18)
      : const Color(0xFF7C423E).withValues(alpha: 0.25);

  // ── Elevation. ──
  // Light: soft, layered, diffuse, faintly blue (landing DESIGN.md). Dark:
  // shadows barely read, so elevation comes mostly from the lighter surface +
  // the hairline; a near-black drop just deepens object cards.
  static const List<BoxShadow> _lCardShadow = [
    BoxShadow(
      color: Color.fromARGB(13, 20, 22, 40),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color.fromARGB(31, 20, 22, 50),
      blurRadius: 30,
      spreadRadius: -10,
      offset: Offset(0, 18),
    ),
  ];
  static const List<BoxShadow> _dCardShadow = [
    BoxShadow(
      color: Color.fromARGB(115, 4, 5, 9),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color.fromARGB(140, 0, 0, 0),
      blurRadius: 28,
      spreadRadius: -10,
      offset: Offset(0, 18),
    ),
  ];
  static List<BoxShadow> get cardShadow => _dark ? _dCardShadow : _lCardShadow;

  static const List<BoxShadow> _lButtonShadow = [
    BoxShadow(
      color: Color.fromARGB(82, 15, 45, 95),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color.fromARGB(128, 30, 80, 160),
      blurRadius: 22,
      spreadRadius: -6,
      offset: Offset(0, 8),
    ),
  ];
  static const List<BoxShadow> _dButtonShadow = [
    BoxShadow(
      color: Color.fromARGB(120, 0, 0, 0),
      blurRadius: 18,
      spreadRadius: -6,
      offset: Offset(0, 8),
    ),
  ];
  static List<BoxShadow> get buttonShadow =>
      _dark ? _dButtonShadow : _lButtonShadow;

  // Subtle neutral lift for small controls (the mobile menu button).
  static const List<BoxShadow> _lControlShadow = [
    BoxShadow(
      color: Color.fromARGB(13, 20, 22, 40),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];
  static const List<BoxShadow> _dControlShadow = [
    BoxShadow(
      color: Color.fromARGB(100, 0, 0, 0),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];
  static List<BoxShadow> get controlShadow =>
      _dark ? _dControlShadow : _lControlShadow;

  // Design values
  static const double radiusBig = 12.0;
  static const double radiusSmall = 8.0;
  // Rounder corner for object cards (landing card cells ≈ 22px).
  static const double radiusCard = 20.0;

  static const double paddingBig = 32;
  static const double paddingSmall = 16;

  static const double spacingBig = 32;
  static const double spacingLarge = 16;
  static const double spacingMedium = 8;
  static const double spacingSmall = 4;
  static const double spacingTiny = 2;

  static final double buttonBorder = 2;
  static final double iconWeight = 300.0;

  // Icon sizes — same Big→Tiny cadence as spacing. Medium (20) is the default.
  static const double iconSizeBig = 32;
  static const double iconSizeLarge = 24;
  static const double iconSizeMedium = 20;
  static const double iconSizeSmall = 18;
  static const double iconSizeTiny = 16;

  static const double buttonBorderSize = 3.0;
  static const double screenHorizontalPadding = 16.0;

  // Left nav rail width. 120 (not 100) so the longest single-word label
  // ("Memberships") fits on one line without overflowing the rail.
  static const double sideNavWidth = 120.0;
  // Width of the left accent bar marking the active nav-rail item.
  static const double navActiveIndicatorWidth = 3.0;
  // The managed gym's logo at the top of the rail.
  static const double navRailLogoSize = 64.0;
  static const double quickListWidth = 240.0;
  static const double tableRowHeight = 35.0;

  // Landing-style top nav (LandingPage/hifi/chrome.jsx GWNav).
  static const double navHeight = 68.0;
  static const double navMaxWidth = 1180.0;
  // Below this width the nav collapses to a hamburger + dropdown (ds.jsx
  // MOBILE_Q `(max-width: 768px)`).
  static const double navMobileBreakpoint = 768.0;
  static const double navMenuButtonSize = 42.0;

  // Two lines of h2, so every reward card's title block is the same height
  // whether the title wraps to one line or two.
  static const double rewardCardTitleHeight = 42;

  // Dialog sizing. The default dialog is a compact confirmation surface;
  // the "wide" variant is a full workflow surface (multi-step wizards) that
  // takes a generous fraction of the viewport — see AppDialog.expanded.
  // Inside a wide dialog the step content keeps a readable measure
  // (dialogContentMaxWidth) centered in the surface.
  static const double dialogMaxWidth = 480.0;
  static const double dialogMaxWidthWide = 1100.0;
  static const double dialogHeightFractionWide = 0.88;
  static const double dialogContentMaxWidth = 760.0;
  // Floor for the wide dialog's height so its fixed chrome (title,
  // stepper, footer) always fits and the scrolling body never gets a
  // negative height; on a viewport too short for this the whole surface
  // scrolls instead of rendering blank.
  static const double dialogMinExpandedHeight = 560.0;
  // Fixed height for a dialog's transient processing/spinner step so the
  // surface doesn't jump in size as it moves form -> processing -> result.
  static const double dialogProcessingHeight = 160.0;

  // Dialog body region heights — fixed so the surface doesn't jump between
  // steps. The scrollable account picker and the waiver markdown editor each
  // hold a fixed area inside the authorized-payer dialogs.
  static const double dialogMemberPickerHeight = 320.0;
  static const double dialogWaiverEditorHeight = 240.0;

  // Shared fixed height for the side-by-side account-history cards (Payment
  // history + Class history). Both cards use it so the row stays equal-height
  // and aligned; each card pins its title and scrolls its rows internally
  // rather than growing the page. Sized to show ~6–7 rows before scrolling.
  static const double historyCardHeight = 560.0;

  // Fixed-height controls (a selector pill, a +/- stepper button).
  static const double pillControlHeight = 40.0;
  static const double stepperButtonHeight = 56.0;

  // Imagery / chart region heights (square assets use the *Size tokens for
  // both width and height).
  static const double heroChartHeight = 200.0;
  static const double rewardThumbnailHeight = 80.0;
  static const double rewardAvatarSize = 72.0;
  static const double qrThumbnailSize = 120.0;
  // A default-image chip in the ImageUploadPickerField pool tray. The chip
  // width follows the field's aspectRatio, so belts render square (64x64)
  // and photos landscape at this height.
  static const double poolChipHeight = 64.0;

  // Rank belt art sizes (square, width == height). A coherent T-shirt scale on
  // the 8pt grid — a legible proportional ladder, not one value per call site.
  static const double rankBeltHero = 120.0; // rank detail page hero
  static const double rankBeltLarge = 96.0; // ladder main-rank card belt
  static const double rankBeltMedium = 64.0; // member-detail + seed-preset tile
  static const double rankBeltSmall = 48.0; // promotable roster row
  static const double rankBeltXSmall =
      40.0; // ladder sub-tile, sub-rank breakdown, promote dialog rows

  // Small glyph-scale boxes — deliberately distinct from iconSize* (reserved
  // for Icon()). Loading spinners and the legend swatch dot.
  static const double spinnerSizeSmall = 20.0;
  static const double spinnerSizeLarge = 32.0;
  static const double legendDotSize = 16.0;

  // Height of the vertical status accent bar beside a status label.
  static const double statusAccentBarHeight = 22.0;

  // Line widths — the standard hairline, the heavier table-row separator, the
  // thin progress / step bar, and the short inline vertical rule's length.
  static const double dividerThickness = 1.0;
  static const double tableRowSeparatorThickness = 2.0;
  static const double progressBarThickness = 4.0;
  static const double verticalDividerHeight = 16.0;

  // Geist — the landing page's typeface (LandingPage/hifi/ds.jsx `sans`).
  static final TextStyle baseFont = GoogleFonts.geist(
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  // Geist Mono — for tracked eyebrow / category micro-labels (ds.jsx `mono`).
  static final TextStyle monoFont = GoogleFonts.geistMono();

  /// H1 text style (bold, 24)
  static TextStyle get h1 => baseFont.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 24,
        color: text,
        letterSpacing: -0.6,
      );

  static TextStyle get h1Regular => h1.copyWith(fontWeight: FontWeight.w500);
  static TextStyle get big1 => h2.copyWith(fontSize: 160);
  static TextStyle get big2 => h2.copyWith(fontSize: 32);

  static TextStyle get big2Bold => big2.copyWith(fontWeight: FontWeight.w700);
  static TextStyle get big2Light => big2.copyWith(fontWeight: FontWeight.w300);

  /// H2 text style (semibold, 16)
  static TextStyle get h2 => baseFont.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 16,
        color: text,
        letterSpacing: -0.2,
      );

  static TextStyle get h2Regular => h2.copyWith(
        fontWeight: FontWeight.w400,
        letterSpacing: 0.03,
      );

  static TextStyle get h2Bold => h2.copyWith(fontWeight: FontWeight.w700);

  /// H3 text style (semibold, 13)
  static TextStyle get h3 => baseFont.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: text,
        letterSpacing: 0,
      );

  static TextStyle get h3Regular => h3.copyWith(fontWeight: FontWeight.w400);

  /// Paragraph text style (regular, 12)
  static TextStyle get p => baseFont.copyWith(
        fontWeight: FontWeight.w400,
        fontSize: 12,
        color: text,
        letterSpacing: 0.03,
      );

  static TextStyle get pBig => p.copyWith(fontSize: 16);
  static TextStyle get pBigBold => pBig.copyWith(fontWeight: FontWeight.w700);
  static TextStyle get pSmall => p.copyWith(fontSize: 11);

  static TextStyle get pSmallBold => pSmall.copyWith(fontWeight: FontWeight.w700);

  static TextStyle get pSemibold => p.copyWith(fontWeight: FontWeight.w600);
  static TextStyle get pBold => p.copyWith(fontWeight: FontWeight.w700);
  static TextStyle get pSmallSemibold =>
      pSmall.copyWith(fontWeight: FontWeight.w600);

  // Landing top-nav text: wordmark + nav links (chrome.jsx GWNav).
  static TextStyle get navWordmark => baseFont.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 18,
        color: text,
        letterSpacing: -0.4,
      );

  static TextStyle get navLink => baseFont.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: 14.5,
        color: text2nd,
        letterSpacing: -0.1,
      );

  // Larger, ink-colored nav link for the mobile dropdown rows.
  static TextStyle get navLinkMobile => baseFont.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: 16,
        color: text,
        letterSpacing: -0.1,
      );

  // Private constructor to prevent instantiation
  DesignConstants._();
}
