import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gives `cached_network_image`'s cache manager somewhere to write.
///
/// It asks `path_provider` for a temp directory the moment a network
/// image resolves, and the plugin has no implementation under
/// `flutter_test` — the resulting [MissingPluginException] surfaces as
/// an uncaught async error and fails the sheet. The request itself still
/// fails (a test has no network), which is the point: the class images
/// land on their placeholder block, and nothing throws getting there.
void stubImageCacheDirectory() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Directory.systemTemp.createTempSync('layout_preview');
  addTearDown(() => dir.deleteSync(recursive: true));
  TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => dir.path,
      );
}

/// A real typeface so the preview sheets show words rather than tofu
/// boxes. Registered under both the brand family and Flutter's default,
/// so it stands in wherever `google_fonts` cannot deliver the real face.
Future<void> loadPreviewFont() async {
  const path = '/usr/share/fonts/liberation-sans-fonts/'
      'LiberationSans-Regular.ttf';
  final file = File(path);
  if (!file.existsSync()) return;
  final bytes = await file.readAsBytes();
  for (final family in ['Jura', 'Roboto']) {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

/// Runs [body] with the font download `google_fonts` cannot complete
/// treated as noise instead of as a test failure.
///
/// Every text style resolves through `GoogleFonts.getFont`, which fires
/// a download the moment a style is built and drops the resulting future
/// on the floor. The preview sheets need [WidgetTester.runAsync] so
/// image codecs actually run, and that same window lets the download
/// run — so on a machine with no network it raises an uncaught error
/// that fails the test. It cannot be drained with `takeException`,
/// because nothing routes it through the framework's pending-exception
/// path; a zone that owns the whole body is the only place to catch it.
///
/// The face loaded by [loadPreviewFont] is what renders instead. Only
/// the font fetch is ignored — every other error still fails the test.
Future<void> runIgnoringFontFetchErrors(Future<void> Function() body) {
  final done = Completer<void>();
  runZonedGuarded(
    () async {
      try {
        await body();
        if (!done.isCompleted) done.complete();
      } catch (error, stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      }
    },
    (error, stack) {
      final text = '$error';
      final isFontFetch =
          text.contains('fonts.gstatic.com') ||
          text.contains('google_fonts') ||
          text.contains('allowRuntimeFetching');
      if (isFontFetch) return;
      if (!done.isCompleted) done.completeError(error, stack);
    },
  );
  return done.future;
}
