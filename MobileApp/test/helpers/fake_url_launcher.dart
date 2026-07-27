import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Stands in for the OS in `url_launcher` tests: records what the app asked it
/// to open instead of actually launching anything. Install it with
/// `UrlLauncherPlatform.instance = FakeUrlLauncher()`.
class FakeUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  FakeUrlLauncher({this.succeeds = true});

  /// Whether the fake OS claims a handler took the intent.
  final bool succeeds;

  final List<String> launched = <String>[];
  LaunchOptions? lastOptions;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => succeeds;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    lastOptions = options;
    return succeeds;
  }
}
