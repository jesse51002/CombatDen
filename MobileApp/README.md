# CombatDen MobileApp (white-label / templated)

A Flutter app **reskinned per tenant**, not a single-brand product. One
codebase; the look is resolved at runtime from a customization preset
produced by the CustomizationService.

## Templating

- The active tenant and design are declared in `lib/core/app_config.dart`
  (`AppConfig.appId` + `AppConfig.designId`).
- The resolved preset lives in
  `../CustomizationService/apps/<appId>/<designId>/` — `customization.yaml`
  (brief + `mode`), `output.yaml` (the resolved palette plus image, font, and
  text slots), `final_images/`.
- Today the customization surface is **colours, images, fonts, and text**. The
  pipeline ships a *finished* palette — it derives the elevated surfaces,
  dividers, popups, and faded variants itself — so the app is a plain consumer
  that reads slots and no longer carries its own surface-derivation math.
- The `lib/customization/` engine resolves each surface at runtime via
  `BrandColor`, `BrandFont`, `BrandText`, and `BrandImage`. Colours, fonts, and
  text fall back to a bundled const default when nothing is loaded.
  **Images have no engine fallback by design:** `BrandImage.of(slot)` returns
  `null` when no customization applies, and the `BrandedImage` widget pairs
  that with the tenant's bundled asset (local-vs-network resolution made a
  built-in fallback more complex than it was worth — the bundled tenant asset
  *is* the fallback).
- **This is just the start.** The templating surface is open-ended — icons and
  animation are next, and over time more of the app (layout, enabled features)
  becomes tenant-customizable. Do not build assuming only colour and text vary;
  never hardcode or assume a single brand's palette, assets, or copy.

## Getting Started

- `flutter pub get`
- `flutter run` (debug) / `flutter run --release`
- `flutter analyze` must be clean before committing.

See `CLAUDE.md` for coding standards and the full customization contract.
