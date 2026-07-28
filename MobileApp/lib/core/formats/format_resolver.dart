import 'package:mobile_app/core/formats/format_overrides.dart';
import 'package:mobile_app/core/formats/format_store.dart';
import 'package:theme_flutter/theme/theme_text.dart';

/// Which layer supplied a format's live value.
enum FormatSource {
  /// The in-app dev picker.
  pinned,

  /// A `--dart-define` passed at launch.
  dartDefine,

  /// The loaded tenant customization.
  tenant,

  /// Nothing above had an opinion, so the value that ships today.
  shipped;

  /// Short label for the dev picker.
  String get label => switch (this) {
    FormatSource.pinned => 'pinned',
    FormatSource.dartDefine => 'dart-define',
    FormatSource.tenant => 'theme',
    FormatSource.shipped => 'ships',
  };
}

/// The ONE place the format precedence chain lives.
///
/// Resolution order, highest first:
///   1. a widget's `formatOverride` argument  (tests, preview sheets)
///   2. [FormatStore]                         (the in-app dev panel)
///   3. [FormatOverrides]                     (`--dart-define`)
///   4. the tenant's customization slot       (production)
///   5. the value that ships today            (fallback)
///
/// Step 1 is per-widget and lives at the call site. Steps 2-5 are here,
/// and `ThemeLayout`, `ThemeMotion` and the dev picker all read through
/// this rather than each walking the chain themselves. That is not
/// tidiness: three hand-written copies is exactly how the picker ended
/// up drawing a value the app was not using, because its copy was
/// missing the tenant step.
///
/// Deliberately built on the engine's existing string-slot reader
/// (`ThemeText.value`) rather than on a new slot kind inside the shared
/// `theme_flutter` package — see `ThemeLayout` for why. `ThemeText`
/// returns the fallback when no customization is loaded, the slot is
/// absent, or DI is not registered (widget tests), and never throws, so
/// every accessor here is safe in every context.
class FormatResolver {
  // Private constructor to prevent instantiation
  FormatResolver._();

  /// The wire value for [slot] and where it came from. The one walk of
  /// the chain; everything else in this class reads off it.
  static (String?, FormatSource) _walk(String slot) {
    final pinned = FormatStore.instance.read(slot);
    if (pinned != null) return (pinned, FormatSource.pinned);
    final override = FormatOverrides.read(slot);
    if (override != null) return (override, FormatSource.dartDefine);
    final tenant = ThemeText.value(slot, fallback: '');
    if (tenant.isNotEmpty) return (tenant, FormatSource.tenant);
    return (null, FormatSource.shipped);
  }

  /// The wire value for [slot], or null when nothing above the shipped
  /// fallback has an opinion. An unrecognised value is left alone here
  /// and degrades to the shipped value in the enum parser.
  static String? read(String slot) => _walk(slot).$1;

  /// The value name [slot] resolves to right now, with [shipped] (an
  /// enum's first value) standing in when nothing else answers.
  static String resolve(String slot, String shipped) =>
      read(slot) ?? shipped;

  /// Which layer [resolve] took its answer from.
  static FormatSource sourceOf(String slot) => _walk(slot).$2;
}
