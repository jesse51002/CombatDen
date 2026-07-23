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
  // Cap on a growth metric table's scroll viewport — about eight rows tall —
  // so a long companion breakdown or member list scrolls internally instead
  // of dictating the tab's height. The section title and the table's own
  // header sit above this cap; only the rows scroll within it.
  static const double growthTableMaxHeight = tableRowHeight * 8;

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
  // The kiosk "Get the app" modal's real scannable download QR (module box).
  static const double kioskAppQrSize = 168.0;

  // ── Kiosk QR contrast — deliberately NOT theme-aware ──
  // A QR code's colours are a FUNCTIONAL requirement, not a themable surface:
  // scanners expect dark modules on a light quiet zone, and many fail (or are
  // slow) on an inverted code. Resolving these through `text` / `surface`
  // rendered the kiosk QR light-on-dark for a gym running the dark theme,
  // silently breaking the app-adoption funnel (and, at Phase G, the live
  // check-in code). So both kiosk QR tiles pin to the light palette's ink +
  // white in EVERY theme. Do NOT "fix" these back onto `text` / `surface` —
  // the inversion is the bug, the theme-independence is the fix. The one
  // renderer is `KioskQrFrame`.
  static const Color kioskQrModule = _lText;
  static const Color kioskQrQuietZone = _lSurface;
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

  // Chart geometry. The stroke of a painted data line — distinct from
  // `dividerThickness` (a hairline), `progressBarThickness` (a progress rail)
  // and `buttonBorder` (a control border). The cap on a bar's thickness is
  // likewise its own token: it coincides with `iconSizeLarge`, but icon sizes
  // are reserved for `Icon()` (the same rule that keeps `legendDotSize` and
  // `spinnerSizeSmall` separate from `iconSize*`).
  static const double chartStroke = 2.0;
  static const double chartBarMaxWidth = 24.0;

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

  // ══ KIOSK TYPE RAMP ══
  // The member kiosk (a supervised iPad read from ~2m) runs its OWN COMPLETE
  // type ramp, transcribed from `KIOSK_MOCKUPS.html` — it does NOT borrow the
  // admin ramp for its smaller text. That is the whole point: a kiosk screen
  // whose headline is kiosk-scale but whose labels are admin-scale reads
  // broken, because the button labels then out-size the copy around them.
  //
  // **The ramp moves as a SET.** Never re-scale one kiosk role on its own —
  // a change here is a change to the whole ladder, and the ordering test in
  // `test/features/kiosk/presentation/kiosk_type_ramp_test.dart` fails if the
  // ladder stops descending. Every kiosk call site reads one of these tokens;
  // none restates a size. The admin ramp (h1/h2/h3/p, `AppPrimaryButton`,
  // `AppOutlineButton`) is untouched by any of it.
  //
  // The ladder, largest first (mockup element in each token's doc):
  //   kioskStreakNum 112 · kioskDisplay 40 · kioskMetric 30 ·
  //   kioskPanelTitle 25 · kioskStatement 22 · kioskFieldText 22 ·
  //   kioskTitle 21 · kioskButtonPrimaryLabel 19 · kioskName 19 ·
  //   kioskSubtitle 18 · kioskButtonOutlineLabel 17 · kioskBody 17 ·
  //   kioskLabel 16 · kioskSectionText 16 · kioskCaption 15 ·
  //   kioskMicro 13 · kioskMonoValue 13 · kioskEyebrow 12 · kioskTag 11
  //
  // Like the other text getters these carry `color: text`; callers apply a
  // muted color where the mockup uses ink-2 (e.g. a section's sub-text via
  // `.copyWith(color: text2nd)`) and a heavier/lighter weight where one mockup
  // element in a role differs (never a different SIZE).
  //
  // **Muted kiosk text is [text2nd], never [text3rd].** `text3rd` (#878D99)
  // measures 3.05:1 on the ground / 3.33:1 on white — under the 4.5:1 WCAG AA
  // floor `PRODUCT.md` holds as a hard requirement, and unreadable anyway on a
  // screen viewed from ~2m. The mockup tints several of these roles `--ink-3`;
  // the kiosk deliberately lifts every one of them that carries WORDS
  // (timer label, section sub-text, eyebrows, search hint + empty line, "or"
  // seam, header kicker, belt names, view counts, the rotate caption) to
  // `text2nd`. `text3rd` survives on kiosk surfaces ONLY for non-text: a
  // hairline, a divider, a progress-bar track, a decorative placeholder glyph.
  // Admin surfaces keep their own `text3rd` usage — that is a separate call.

  /// The post-check-in glance's hero streak numeral — 112px bold, sized for the
  /// 2-metre glance (bigger than the whole admin ramp, which tops out at
  /// big2/32). Mockup `.streak-num`. Carries `color: text` like the other kiosk
  /// display tokens; the glance recolors it to the brand via
  /// `.copyWith(color: primaryColor)` (the numeral is always sapphire).
  static TextStyle get kioskStreakNum => baseFont.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 112,
        color: text,
        letterSpacing: -5.6,
      );

  /// A kiosk SCREEN's title — the one line that anchors the whole view
  /// ("Check in", "Hi Marcus, pick your class", "Nice one, Marcus.", "Let's
  /// sort this at the front desk"). 40px bold. Mockup `.home-title h1` /
  /// `.blocked h1` (40) and `.screen-head h1` / `.glance-top h1` (42) — one
  /// token for all four, at the pair's lower value.
  static TextStyle get kioskDisplay => baseFont.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 40,
        color: text,
        letterSpacing: -1.2,
      );

  /// A big NUMBER inside a kiosk panel — the glance's points balance, and (at
  /// w600) the "week streak" word under the hero numeral. Mockup `.points .n`
  /// (30/700) and `.streak-word` (29/600).
  static TextStyle get kioskMetric => baseFont.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 30,
        color: text,
        letterSpacing: -0.9,
      );

  /// A kiosk PANEL's own title — the "Get the app" card's heading, the
  /// showcase's rotating slide title, the idle-warning card. 25px bold, one
  /// clear step under [kioskDisplay] so a panel never competes with the
  /// screen. Mockup `.app-card-title`.
  static TextStyle get kioskPanelTitle => baseFont.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 25,
        color: text,
        letterSpacing: -0.5,
      );

  /// ONE important sentence set apart — the blocked screen's why-box reason,
  /// and a class card's name on the kiosk class pick. Mockup
  /// `.why-box .why-reason` (22/600) / `.class-name` (23/600).
  static TextStyle get kioskStatement => baseFont.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 22,
        color: text,
        letterSpacing: -0.35,
      );

  /// The kiosk's one text INPUT — the name-search field's typed text and its
  /// hint. Deliberately large and light: a member types it standing up, from
  /// arm's length. Mockup `.search-field .ph`.
  static TextStyle get kioskFieldText => baseFont.copyWith(
        fontWeight: FontWeight.w400,
        fontSize: 22,
        color: text,
        letterSpacing: -0.22,
      );

  /// A SECTION head inside a kiosk screen ("Scan with app" / "Name search") —
  /// 21px semibold. Mockup `.sub-title`.
  static TextStyle get kioskTitle => baseFont.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 21,
        color: text,
        letterSpacing: -0.2,
      );

  /// A NAME rendered as a tap target or an identity — a search result row, the
  /// gym's name in the kiosk header. 19px semibold (it coincides with
  /// [kioskButtonPrimaryLabel]; the mockup sizes both at 19). Mockup
  /// `.name-row .nm` / `.wordmark`.
  static TextStyle get kioskName => baseFont.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 19,
        color: text,
        letterSpacing: -0.19,
      );

  /// The muted explanatory line under a [kioskDisplay] SCREEN title — the class
  /// pick's "Open for check-in right now…", the blocked screen's reassurance,
  /// the closing screen's line. Mockup `.screen-head .sub` / `.blocked-rea`.
  static TextStyle get kioskSubtitle => baseFont.copyWith(
        fontWeight: FontWeight.w400,
        fontSize: 18,
        color: text,
        letterSpacing: 0,
      );

  /// Body copy inside a kiosk panel — the streak's keep-it-alive note, and (at
  /// w600) the "points" unit beside the balance. Mockup `.streak-note` (17/400)
  /// / `.points .u` (17/600).
  static TextStyle get kioskBody => baseFont.copyWith(
        fontWeight: FontWeight.w400,
        fontSize: 17,
        color: text,
        letterSpacing: 0,
      );

  /// A strong small LABEL on a kiosk surface — a week-strip day letter, the
  /// "+N pts" chip (w700), a reward tile's title and its points line (w700), a
  /// class card's time / instructor line (w500). Mockup `.day-badge .dl` /
  /// `.earned-chip` / `.reward-name` / `.reward-pts` / `.class-when`.
  static TextStyle get kioskLabel => baseFont.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 16,
        color: text,
        letterSpacing: -0.16,
      );

  /// The muted explanatory line under a [kioskTitle] SECTION head — the home
  /// halves' "Scan QR code with app for instant check in". One step under
  /// [kioskSubtitle] because it answers a 21px head, not a 40px title. Mockup
  /// `.sub-text`.
  static TextStyle get kioskSectionText => baseFont.copyWith(
        fontWeight: FontWeight.w400,
        fontSize: 16,
        color: text,
        letterSpacing: 0,
      );

  /// A quiet supporting line — the app-adoption nudge, the auto-return
  /// countdown, a sign-in step, a benefit check, a showcase slide's caption.
  /// Mockup `.app-line` / `.timer-label` / `.step-t` / `.app-benefits .b` /
  /// `.slide-copy`.
  static TextStyle get kioskCaption => baseFont.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: 15,
        color: text,
        letterSpacing: 0,
      );

  /// The smallest kiosk label — the "or" seam badge, a reward tile's
  /// "{balance} / {cost}" fraction, a showcase video's title, the numbered
  /// step discs, the marketing Book pill. Mockup `.seam-badge` /
  /// `.reward-pts.frac` / `.vcard-title` / `.step-n` / `.bc-book`.
  static TextStyle get kioskMicro => baseFont.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: text,
        letterSpacing: -0.13,
      );

  /// A literal value rendered as a kiosk chip — the sign-in email on the "Get
  /// the app" card's step 2 (mockup `.step-email`). Geist Mono at body size so
  /// an address reads unambiguously (l/1, O/0), untracked — unlike
  /// [kioskEyebrow], which is a tracked uppercase micro-label.
  static TextStyle get kioskMonoValue => monoFont.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: text,
        letterSpacing: 0,
      );

  /// The kiosk's tracked mono eyebrow ("YOUR POINTS", "IN THE APP", "WHY") — a
  /// Geist-Mono micro-label above the thing it names. Muted and letter-tracked.
  /// Mockup `.eyebrow` (which tints it `--ink-3`; the kiosk lifts every muted
  /// WORD to [text2nd] — see the contrast note at the top of this ramp).
  static TextStyle get kioskEyebrow => monoFont.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 12,
        color: text2nd,
        letterSpacing: 1.9,
      );

  /// A TAG pinned on artwork or the tiniest meta line — a reward tile's price
  /// pill, the rank ladder's belt names and "You're here" pill, a showcase
  /// video's view count (w500). The one kiosk role the mockup keeps genuinely
  /// tiny: it always sits ON an image or inside a dense strip. Mockup
  /// `.price-pill` / `.belt-tag` / `.belt-here` / `.vcard-views`.
  static TextStyle get kioskTag => baseFont.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 11,
        color: text,
        letterSpacing: -0.11,
      );

  /// Inner content measure for the glance's two panels — the width the reward
  /// tile grid and the week-day strip are capped at (and centered within)
  /// inside a panel, so neither spreads edge-to-edge on the wide kiosk. One
  /// token unifies the mockup's `.reward-grid` (max 292) and `.week-strip`
  /// (max 360) caps into a single kiosk content width.
  static const double kioskGlanceMeasure = 320.0;

  /// One video card on the "Watch videos" showcase slide (mockup `.vc-grid`,
  /// two 198px columns in a 410px grid). Wider than half of
  /// [kioskGlanceMeasure] on purpose: a video card carries a 16:9 thumbnail
  /// AND a title line, so squeezing it to the reward-tile measure crushes
  /// both.
  static const double kioskVideoCardWidth = 192.0;

  // ── Kiosk button scale ──
  // The kiosk is read (and pressed) from standing distance on a supervised
  // iPad, so its buttons run a full step larger than the admin defaults
  // (13px label / 16x8 padding). They are two rungs OF the kiosk ramp above,
  // not a separate scale — the primary label sits with [kioskName] (19) and
  // the outline label between [kioskSubtitle] (18) and [kioskBody] (17),
  // exactly as the mockup pairs them. Mockup `.btn-primary` /
  // `.btn-outline`. Applied ONLY through `KioskPrimaryButton` /
  // `KioskOutlineButton`
  // (`features/kiosk/presentation/widgets/kiosk_buttons.dart`) so the whole
  // kiosk button set scales together and no call site restates a size; the
  // admin app keeps the `AppPrimaryButton` / `AppOutlineButton` defaults.

  /// Kiosk PRIMARY button label — 19px semibold (mockup `.btn-primary`).
  static TextStyle get kioskButtonPrimaryLabel => baseFont.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 19,
        color: text,
        letterSpacing: -0.19,
      );

  /// Kiosk OUTLINE button label — 17px semibold (mockup `.btn-outline`).
  static TextStyle get kioskButtonOutlineLabel => baseFont.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 17,
        color: text,
        letterSpacing: -0.17,
      );

  /// Kiosk PRIMARY button box — 18/34 (mockup `.btn-primary` padding).
  static const EdgeInsets kioskButtonPrimaryPadding = EdgeInsets.symmetric(
    horizontal: 34,
    vertical: 18,
  );

  /// Kiosk OUTLINE button box — 15/30 (mockup `.btn-outline` padding). One
  /// step tighter than the primary, exactly as the mockup pairs them.
  static const EdgeInsets kioskButtonOutlinePadding = EdgeInsets.symmetric(
    horizontal: 30,
    vertical: 15,
  );

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
