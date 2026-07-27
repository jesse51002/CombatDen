# CombatDen MobileApp (white-label / templated)

The CombatDen **member-facing app** — a Flutter app **reskinned per tenant**, not
a single-brand product. It is live: Supabase auth, and real member data from the
FastApiBackend **member portal** (`/api/v1/member/...`) over an authenticated
`dio` client. One codebase; the look is resolved at runtime from a customization
preset produced by the **ThemeService**.

## Templating

- The active tenant and the **boot/fallback** design are declared in
  `lib/core/app_config.dart` (`AppConfig.appId` + `AppConfig.designId`). Once a
  member signs in, the app re-themes to that member's gym design (the gym's saved
  `theme_design_id`, read from `GET /api/v1/gyms/{id}/showcase`) via
  `ThemeRuntime.selectDesign`.
- A preset lives in `../ThemeService/apps/<appId>/<designId>/` —
  `customization.yaml` (brief + `mode`), `output.yaml` (the resolved palette plus
  image, font, and text slots), `final_images/`.
- The shared **`theme_flutter`** package (path dep `../ThemeService/ThemeFlutter`)
  is the runtime: it fetches the resolved preset, disk-caches the last-good copy,
  and resolves each slot at runtime, driving the runtime-backed
  `DesignConstants`. Colours, fonts, and text fall back to a bundled const default
  when nothing is loaded; images fall back to the bundled tenant asset.
- **This is just the start.** The templating surface is open-ended — over time
  more of the app (layout, enabled features) becomes tenant-customizable. Don't
  build assuming only colour and text vary; never hardcode or assume a single
  brand's palette, assets, or copy.

## Getting Started

- `flutter pub get`
- `flutter run` (debug) / `flutter run --release` — the live app needs the backend
  on `:8000`, Supabase, and a seeded member (`make run` wires the dev auto-login
  dart-defines). A fresh worktree needs `setup_worktree_env.sh` first (it copies
  the gitignored `.env.*` files).
- `flutter analyze` must be clean before committing.

See `CLAUDE.md` for coding standards, the backend/member-portal contract, and the
full customization contract.
