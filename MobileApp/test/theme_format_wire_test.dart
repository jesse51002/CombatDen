import 'package:flutter_test/flutter_test.dart';
import 'package:theme_flutter/data/models/customization.dart';

import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/formats/format_resolver.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/core/formats/theme_layout.dart';

import 'helpers/stub_theme_service.dart';

/// The wire contract for formats.
///
/// This exists because the app got it wrong in exactly one way and the
/// symptom was silence: the generator writes its chosen arrangements to
/// `format_set.formats`, the app read them from `text_set.texts`, and a
/// missing slot is a *supported* state that falls back to the shipped
/// arrangement. So every themed screen rendered the default and nothing
/// logged, warned or failed. These tests pin the section name, the entry
/// shape, and the fallback, so that failure mode cannot come back
/// quietly.
void main() {
  /// A trimmed copy of a real ThemeService response. Shape is verbatim
  /// from `GET /apps/combatden/<design>` — including the `overwrite_specs`
  /// the client ignores and the `reason` it keeps.
  Map<String, dynamic> wire() => {
    'app': 'combatden',
    'display_name': 'CombatDen',
    'design_name': 'Strike Kickboxing',
    'color_set': {'mode': 'dark', 'colors': {}, 'palette': {}},
    'images': {},
    'fonts': {},
    'icons': {},
    'text_set': {
      'texts': {
        'reserve_cta': {'value': 'Throw down'},
      },
    },
    'format_set': {
      'formats': {
        'app_shell_format': {
          'overwrite_specs': {'specs': '', 'image_to_image': null},
          'value': 'compactRail',
          'reason': 'The brief demands bright, fast and social.',
        },
        'home_format': {
          'overwrite_specs': {'specs': '', 'image_to_image': null},
          'value': 'nextUpHero',
          'reason': "The brief emphasizes what's next.",
        },
      },
    },
  };

  group('the engine parses the wire section the generator writes', () {
    test('formats come from format_set, not text_set', () {
      final config = ThemeConfig.fromJson(wire());

      expect(config.formats.keys, containsAll(<String>[
        CombatDenSlots.appShellFormat,
        CombatDenSlots.homeFormat,
      ]));
      expect(config.formats[CombatDenSlots.homeFormat]!.value, 'nextUpHero');

      // The section that is NOT formats stays brand copy, and must not
      // start carrying arrangements.
      expect(config.texts['reserve_cta'], 'Throw down');
      expect(config.texts.keys.where((k) => k.endsWith('_format')), isEmpty);
    });

    test('the generator rationale survives parsing', () {
      final config = ThemeConfig.fromJson(wire());
      expect(
        config.formats[CombatDenSlots.appShellFormat]!.reason,
        contains('bright, fast and social'),
      );
    });

    test('a malformed slot is skipped, not fatal to the payload', () {
      final payload = wire();
      (payload['format_set']
              as Map<String, dynamic>)['formats']
          as Map<String, dynamic>
        ..['rank_format'] = {'reason': 'no value at all'}
        ..['videos_format'] = {'value': ''};

      final config = ThemeConfig.fromJson(payload);
      expect(config.formats.containsKey('rank_format'), isFalse);
      expect(config.formats.containsKey('videos_format'), isFalse);
      // The good slots still arrive.
      expect(config.formats[CombatDenSlots.homeFormat]!.value, 'nextUpHero');
    });

    test('a payload with no format_set is a supported state', () {
      final payload = wire()..remove('format_set');
      expect(ThemeConfig.fromJson(payload).formats, isEmpty);
    });
  });

  group('a themed arrangement reaches the screen', () {
    late void Function() teardown;

    setUp(() => teardown = installStubTheme(StubThemeService()));
    tearDown(() => teardown());

    test('the tenant value wins over the shipped arrangement', () {
      // Unthemed: the app renders what it ships.
      expect(ThemeLayout.home(), HomeFormat.agendaList);

      final service = StubThemeService({
        CombatDenSlots.homeFormat: 'nextUpHero',
      });
      final down = installStubTheme(service);
      addTearDown(down);

      expect(ThemeLayout.home(), HomeFormat.nextUpHero);
      expect(FormatResolver.sourceOf(CombatDenSlots.homeFormat),
          FormatSource.tenant);
    });

    test('a vocabulary the service is ahead of degrades, never breaks', () {
      final service = StubThemeService({
        CombatDenSlots.homeFormat: 'someLayoutThisClientHasNeverHeardOf',
      });
      final down = installStubTheme(service);
      addTearDown(down);

      // The engine passes the string through unvalidated; the app's own
      // parser is what refuses it, and it refuses it to the arrangement
      // it ships rather than to an error.
      expect(ThemeLayout.home(), HomeFormat.agendaList);
    });
  });
}
