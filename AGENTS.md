# Repository Guidelines

## Project Structure & Module Organization

`merry` is a Dart CLI with a small Rust native library for process handling. Entry points live in `bin/` and `lib/`, with implementation grouped under `lib/src/commands`, `lib/src/utils`, `lib/src/error`, and `lib/src/bindings`. Precompiled native artifacts are checked in under `lib/src/blobs/`. Rust sources and release settings live in `native/`. Tests are in `test/`, and the sample package used for manual verification lives in `example/`. CI workflows are in `.github/workflows/`.

## Build, Test, and Development Commands

- `dart pub get`: install Dart dependencies.
- `dart analyze`: run the repository lint set from `analysis_options.yaml`.
- `dart test`: run the unit test suite in `test/`.
- `dart run build_runner build --delete-conflicting-outputs`: regenerate Mockito mocks after changing `@GenerateMocks`.
- `dart run bin/merry.dart ls -d`: inspect available scripts and descriptions from the local checkout.
- `dart run bin/merry.dart test`: run the repo-defined `test` script from `merry.yaml`.
- `cd native && cargo build --release`: build the Rust library manually.
- `dart run bin/merry.dart build linux-x64`: rebuild and copy a platform blob using the scripted workflow.

## Coding Style & Naming Conventions

Use standard Dart formatting with 2-space indentation and run `dart format .` before submitting changes. Follow the existing lint policy: prefer `package:` imports, explicit return types, and strong typing over `dynamic`. Use `UpperCamelCase` for types, `lowerCamelCase` for members, and `snake_case.dart` for filenames. Keep CLI-facing behavior in `lib/src/commands/`; keep parsing, YAML, and reference helpers in `lib/src/utils/`.

## Testing Guidelines

Tests use `package:test` with `mockito` for file system doubles. Name files `*_test.dart` and keep generated mocks alongside the test file, as in `test/utils_test.dart` and `test/utils_test.mocks.dart`. Add focused tests for command parsing, YAML script resolution, positional arguments, and error handling whenever behavior changes. No coverage gate is configured, so rely on targeted regression tests.

## Commit & Pull Request Guidelines

Recent history uses Conventional Commit prefixes such as `feat:`, `style:`, `ci:`, and `chore:`. Keep subjects short, imperative, and scoped to one change. Pull requests should explain user-visible CLI changes, note affected platforms when touching `lib/src/blobs/` or `native/`, link the related issue when applicable, and include sample output or screenshots for changes to `ls`, JSON output, or docs.
