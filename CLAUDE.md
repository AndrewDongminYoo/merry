# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About

**merry** is a Dart CLI script manager — a maintained fork of `derry`. It lets developers define shell command shortcuts in `pubspec.yaml` or `merry.yaml` and run them with `merry <name>`.

## Commands

```bash
# Run all tests
dart run test

# Run a single test file
dart run test test/utils_test.dart

# Lint
dart analyze

# Regenerate mocks (after changing @GenerateMocks annotations)
dart run build_runner build --delete-conflicting-outputs
```

### Building native blobs (Rust FFI)

Only needed when `native/src/lib.rs` changes. Blobs are pre-compiled and committed to `lib/src/blobs/`.

```bash
# macOS ARM64
cd native && cargo build --release && cd ..
cp native/target/release/libmerry.dylib lib/src/blobs/macos_arm64.dylib

# macOS x64
cp native/target/release/libmerry.dylib lib/src/blobs/macos_x64.dylib

# Linux x64
cp native/target/release/libmerry.so lib/src/blobs/linux_x64.so
```

## Architecture

### Entry point & command dispatch

`bin/merry.dart` sets up an `args` `CommandRunner` with four subcommands: `run`, `ls`, `source`, `upgrade`. **Unknown commands fall through to `run`** — this is why `merry build` works without typing `merry run build`. The fallback is implemented by catching `UsageException` in the runner's error handler and re-dispatching.

### Core execution path

```log
bin/merry.dart
  └─ commands/run.dart          # resolves script name, reads pubspec
       └─ ScriptsRegistry       # lib/src/utils/scripts_registry.dart
            ├─ resolves $references, variable substitution, positional args ($1 $2)
            ├─ runs pre/post hooks
            └─ bindings/run_script.dart   # Dart FFI wrapper
                 └─ lib/src/blobs/*.{so,dylib,dll}  # compiled Rust
                      └─ native/src/lib.rs  # shell spawn, signal forwarding, exit code
```

### ScriptsRegistry (central coordinator)

`lib/src/utils/scripts_registry.dart` — uses **static memoization caches** (`scripts`, `paths`, `serializedDefinitions`, `references`, `variables`, `aliasMap`). All caches must be cleared between test runs; tests set them directly via `ScriptsRegistry.scripts = ...`.

### Configuration loading

`lib/src/utils/pubspec.dart` lazy-loads `pubspec.yaml`. The `scripts:` key can be either an inline map **or a string path** to an external file (e.g., `scripts: merry.yaml`). The indirection is resolved transparently.

### Definition

`lib/src/utils/definition.dart` is the parsed form of a single script entry. `Definition.from(dynamic)` handles three YAML shapes:

- `String` — single command
- `List` — sequence of commands
- `Map` — map with optional `$description`, `$workdir`, and per-platform keys

### FFI layer

`lib/src/bindings/run_script.dart` loads the platform-appropriate blob at runtime and calls `run_script(String cmd) → int`. The Rust side (`native/src/lib.rs`) spawns a shell process, forwards Ctrl+C via the `ctrlc` crate, and returns the child exit code.

### Error handling

`lib/src/error/error_code.dart` defines ~15 typed error codes. `MerryError` carries a type + body map. `handle_error()` formats and prints the error, with string-similarity suggestions for typo'd script names.

## Testing

Tests live in `test/utils_test.dart`. Filesystem is mocked with `IOOverrides` + mockito-generated `MockFile`/`MockDirectory`. After editing `@GenerateMocks(...)`, regenerate with `build_runner` before running tests.
