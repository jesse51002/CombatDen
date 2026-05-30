import 'package:get_it/get_it.dart';

/// Internal service locator for the customization package.
///
/// App code never touches this — bootstrap via
/// `ThemeRuntime.initialize`. It exists only so the
/// context-free resolvers (`ThemeColor` / `ThemeImage`) can
/// reach the loaded `ThemeService` from anywhere.
final GetIt getIt = GetIt.instance;
