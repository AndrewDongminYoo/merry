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

Blobs are pre-compiled and committed to `lib/src/blobs/`. Nothing in the release path compiles `native/` — the FFI loader opens the checked-in files — so **a `native/` change only takes effect once the blobs are rebuilt**.

The blobs for all four platforms come from the `Compile blobs` workflow (`build.yml`), which is **`workflow_dispatch` only — it does not run on push or PR**. After changing `native/`:

```bash
# dispatch against the branch, not main: the blob PR then targets that branch
# and both can merge together
gh workflow run build.yml --repo AndrewDongminYoo/merry --ref <branch>
```

It opens a `ci: update precompiled blobs` PR into the ref it ran on. Merge that first, then the branch.

A stale blob set is caught by `.github/scripts/check-blobs.sh`, which compares a hash of `native/src/*.rs` + `Cargo.toml` + `Cargo.lock` against `lib/src/blobs/native.sha256`. It gates both `verify.yml` (PR, push to main) and `publish.yml` (tag), and runs locally:

```bash
.github/scripts/check-blobs.sh          # verify — fails if native/ moved on without a rebuild
.github/scripts/check-blobs.sh write    # record the hash (build.yml does this; rarely needed by hand)
```

Do **not** hand-copy a locally built blob into a commit: only the host's own platform gets rebuilt, leaving the other three mismatched. Build locally for testing, then restore with `git checkout lib/src/blobs/`.

```bash
# local build, for testing on this machine only
cd native && cargo build --release && cd ..
cp native/target/release/libmerry.dylib lib/src/blobs/macos_arm64.dylib
# ... test ...
git checkout lib/src/blobs/macos_arm64.dylib
```

### Testing signal handling

Ctrl+C and terminal job control cannot be exercised without a pty. `script` or `expect` provides one:

```bash
# an interactive script must not hang (SIGTTIN) — it should read stdin
expect -c 'spawn merry prompt; expect "name: "; send "Jane\r"; expect eof'

# a stopped child shows STAT=T
ps -ax -o pid,pgid,stat,command | grep '[s]leep 300'
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

## Working with GitHub here

This repo is a maintained fork of `derry` **by lineage, not by GitHub** — `isFork=false`, and clones usually carry an `upstream` remote pointing at `frencojobs/derry`. `gh` picks its base repo from `remote.<name>.gh-resolved` in `.git/config`, which is untracked, so a fresh clone can resolve the base to `frencojobs/derry` and aim `gh pr create` at someone else's repository.

Check once per clone, and fix it rather than passing `--repo` to every command:

```bash
gh repo set-default --view              # expect AndrewDongminYoo/merry
gh repo set-default AndrewDongminYoo/merry
```

`merry` is its own package and never sends PRs upstream; the `upstream` remote is only for reading derry's history.

## Testing

Tests live in `test/utils_test.dart`. Filesystem is mocked with `IOOverrides` + mockito-generated `MockFile`/`MockDirectory`. After editing `@GenerateMocks(...)`, regenerate with `build_runner` before running tests.
