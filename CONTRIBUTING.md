# Contributing to Mojac

Thanks for taking the time to improve Mojac. This project is a small Flutter
application, so the contribution process is deliberately lightweight.

## Before you start

- Search existing issues and pull requests to avoid duplicate work.
- Open an issue for larger changes (new parsers, platform targets, dependency
  swaps) before writing a lot of code.
- Do not commit generated `android/`, `linux/`, `build/`, `dist/` or `.flutter/`
  directories. `tool/bootstrap.sh` recreates the platform shells.
- Do not commit playlists, XMLTV files, credentials, API keys, keystores or
  screenshots containing private channel data.

## Development setup

```bash
git clone https://github.com/mmbesar/Mojac.git
cd Mojac
tool/bootstrap.sh
flutter pub get
```

`tool/bootstrap.sh` needs Flutter 3.47.8 on `PATH` (or it clones it into
`./.flutter`). See [docs/BUILDING.md](docs/BUILDING.md) for the Android SDK,
Linux GTK/libmpv packages and ARM64 notes.

## Checks

Run these before opening a pull request:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-fatal-infos
flutter test
```

CI runs the analyzer and tests on every push and pull request. Android and
Linux builds are only produced in CI; you do not need to build all four
artifacts locally to get a change reviewed.

## Code guidelines

- Keep the layering intact: parsing and data in `lib/data`, platform/theme/Bidi
  helpers in `lib/core`, presentation in `lib/ui`, and user-visible strings in
  `lib/l10n/strings.dart`.
- Add both English and Arabic text for every new user-visible string.
- Use `BidiText` for mixed Arabic/Latin content, especially channel names,
  programme titles, descriptions and error messages. Do not wrap bidi text in a
  fixed `TextDirection`.
- Prefer the existing Catppuccin theme extension (`context.mojacColors`) over
  hard-coded colours. AMOLED and dynamic colour must keep working.
- Keep the source cache keyed by source id; never merge channels or programmes
  from different sources.
- Add tests for parser changes. A small fixture string in `test/` is preferred
  over a binary playlist.
- Avoid new dependencies unless they are necessary and actively maintained.
  Explain the trade-off in the pull request.

Formatting is enforced with `dart format`; the analyzer config lives in
`analysis_options.yaml`.

## Pull requests

- Keep each pull request focused on one change.
- Describe the user-visible effect and how you tested it. Mention if you could
  not build a platform locally.
- Reference related issues with `Fixes #123` where appropriate.
- Update `CHANGELOG.md` for user-visible changes.
- Be patient: reviews are done on a best-effort basis.

## Commits

Use short imperative subjects, for example:

```
Fix XMLTV channel matching for empty ids
Add Arabic labels for the source editor
```

Group related changes into one commit rather than dozens of tiny commits. Do not
rewrite published history on `main`; use a feature branch and a pull request.

## Licensing

Mojac is GPL-3.0-or-later. By submitting a contribution you agree that it may be
distributed under the same license. Only submit code and assets you have the
right to license this way. The bundled Noto Sans Arabic font is OFL-1.1; keep
`assets/fonts/OFL.txt` with any redistributed copy.
