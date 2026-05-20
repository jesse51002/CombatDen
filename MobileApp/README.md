# CombatDen MobileApp (white-label / templated)

A Flutter app **reskinned per tenant**, not a single-brand product. One
codebase; the look is resolved at runtime from a customization preset
produced by the CustomizationService.

## Templating

- The active tenant and design are declared in `lib/core/app_config.dart`
  (`AppConfig.appId` + `AppConfig.designId`).
- The resolved preset lives in
  `../CustomizationService/apps/<appId>/<designId>/` — `customization.yaml`
  (brief + `dark_mode`), `output.yaml` (resolved colour/image slots),
  `final_images/`.
- Today the customization surface is colours (4 slots) and imagery; the app
  derives every other token (elevation, dividers, popups) from those.
- **This is just the start.** The templating surface is open-ended — over
  time more of the app (copy, layout, enabled features) becomes
  tenant-customizable. Do not build assuming only colour and text vary;
  never hardcode or assume a single brand's palette, assets, or copy.

## Getting Started

- `flutter pub get`
- `flutter run` (debug) / `flutter run --release`
- `flutter analyze` must be clean before committing.

See `CLAUDE.md` for coding standards and the full customization contract.
