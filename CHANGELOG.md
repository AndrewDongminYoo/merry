## [2.4.0] - 2026-08-31

### Added

- `merry ls --output=tasks` generates a VS Code `tasks.json` file.
  Each script becomes a task that runs it through the local `merry:merry` executable,
  while `pre`/`post` hooks are left out because they run together with their own script.

### Internal

- Raise the `yaml` constraint to `^3.1.4`, which reports a self-referential collection as a parse error instead of overflowing the stack on it

## [2.3.0] - 2026-08-13

### Fixed

- Propagate fail-fast execution through referenced scripts, so a failed command in a referenced pre-hook stops its remaining commands instead of continuing
- Generate `build_runner` scripts without the removed `--delete-conflicting-outputs` option in `merry init`, and update the project scripts and examples to match

### Internal

- Upgrade Dart dependencies and Checkov, adapt `MerryError` to Equatable 2.1, and regenerate Mockito mocks with the updated toolchain

## [2.2.0] - 2026-08-06

### Added

- `merry init` writes a starter script file for the current project and links it from `pubspec.yaml`. The generated scripts follow what the project declares: build targets come from the platform directories that exist, `generate` from a `build_runner` dependency, and a Flutter plugin's `dev` script runs its `example/` app. A project configured with inline scripts is left untouched, and an existing script file is replaced only after confirmation. The write target is constrained the way reading already constrains it — a path escaping the project, a symlink resolving out of it, a hard link to the manifest, or `pubspec.yaml` itself is refused before anything is written, and the `pubspec.yaml` link is appended (or inserted before a `...` document terminator) so comments and blank lines stay where their author put them

## [2.1.4] - 2026-07-30

### Fixed

- Run `merry upgrade` through the Dart SDK that launched the process instead of a shell command; the self-upgrade previously failed outright with ``Could not find package `pub` `` and resolved `dart` from `PATH`
- Report the running version from `merry --version`, which had been stuck at 2.1.2 since the 2.1.3 release
- Reject a circular `$script` reference with an error naming the cycle, instead of looping until the process is killed
- Constrain an external `scripts:` file to the project directory. A value that escapes it — an absolute path such as `scripts: /etc/hosts`, or a symlink pointing outside — is now refused. In-project filenames like `scripts: merry.yaml` are unaffected, but a deliberate `scripts: ../shared/merry.yaml` no longer resolves

### Internal

- Run the test suite on pull requests and pushes to main; it previously ran only on a release tag, so a regression could reach main and surface at publish time
- Pin every workflow checkout to a commit SHA and stop it persisting a repository credential, with a test sweeping all workflows for both
- Upgrade trunk linters, and enable clippy, shellcheck and shfmt

## [2.1.3] - 2026-07-25

### Fixed

- Refuse to run a script when a substituted positional argument or `(variables)` value contains shell-active characters, closing quote-context command injection
- Reject cyclic YAML map aliases used as mapping keys instead of overflowing the stack and crashing commands such as `merry ls`
- Abort a script when its pre-hook fails, including list-valued pre-hooks whose later commands previously masked the failure
- Reject unknown `(execution)` values instead of silently degrading to `multiple`, restoring once-mode fail-fast execution, and expose the execution mode in `merry ls --output=json`
- Stop the remaining script list after Ctrl+C (SIGINT), and propagate a post-hook's SIGINT instead of reporting success

### Internal

- Harden the native blob workflow (pin rust-toolchain to stable alongside the SHA pin)
- Isolate pub publish credentials in the publishing workflow

## [2.1.2] - 2026-07-24

### Fixed

- Reject invalid CLI options and unexpected arguments with usage errors instead of crashing, including when the script configuration is empty
- Preserve quoting and argument boundaries for positional arguments and referenced scripts, including backslash escapes
- Keep interactive scripts attached to the terminal and reliably terminate their entire process group on Ctrl+C
- Preserve runnable command groups and surrounding metadata when listing or resolving platform-specific and default scripts
- Treat configured POSIX working directories as literal shell data so command substitutions are not evaluated

### Internal

- Bind checked-in native blobs to all tracked Cargo inputs, including symlinks, executable modes, workspace members, and repository Cargo configuration
- Restrict the OIDC publishing workflow to strict `vMAJOR.MINOR.PATCH` tags

## [2.1.1] - 2026-04-25

### Fixed

- Processes terminated by a signal now report the conventional `128 + signal_number`
  exit code on Unix (e.g. 130 for Ctrl+C / SIGINT) instead of always returning 1
- Script definitions with a non-string, non-list `(scripts)` value now throw a
  descriptive `ArgumentError` instead of a cryptic runtime cast failure

### Internal

- FFI: close Ctrl+C race window between `SharedChild::spawn` and `CURRENT_CHILD`
  storage; add named return-code constants; swap four `#[cfg]` blocks for a single
  tuple expression; replace silent mutex-poison swallow with `expect()`
- Dart: parameterize `CommandRunner` and all `Command` subclasses as `<int>`;
  make every `run()` return `Future<int>`; add explicit type arguments throughout
  to satisfy `strict-raw-types` and `strict-inference` analyzer options
- Remove unused `console` and `collection` dependencies
- Remove Flutter-only lint rules from `analysis_options.yaml`
- Integrate Trunk.io for linting and formatting
- Upgrade Cargo dependencies and update precompiled native blobs

## [2.1.0] - 2026-04-25

### Added

- `merry ls --output=json` — Machine-readable JSON output listing all scripts
  with `name`, `commands`, `description`, `workdir`, `hooks`, and `hook_for`
  fields; use `--output=tree` (default) for the existing human-readable tree

### Changed

- JSON output is indented with 2 spaces for readability
- FFI native library is now loaded once per process, reducing per-call overhead

### Fixed

- `run_script` now handles a null pointer and invalid UTF-8 gracefully instead
  of panicking, making script execution more resilient
- `getPaths()` correctly includes a group key when all its sub-keys are
  metadata entries (e.g. a map containing only `(description)`)

### Internal

- CI: migrate blob build runners away from retired GitHub-hosted images
- CI: add required workflow permissions
- Refactor `Pubspec` and `ScriptsRegistry` to use instance fields instead of
  static state, improving isolation and testability
- Refactor test suite to remove shared static state between test cases
- Free native UTF-8 buffer after FFI call to prevent memory leak

## 2.0.0

**Merry** is a maintained fork of [derry](https://pub.dev/packages/derry) by
[Frenco](https://github.com/frencojobs), which has been unmaintained since
February 2023. All original functionality is preserved and the script
definition format is fully compatible — only the CLI command name changes.

### Breaking changes

- Package renamed from `derry` to `merry`; CLI command is now `merry`
- Minimum Dart SDK raised to `>=3.10.4`
- Scripts definition file is now named `merry.yaml` by convention (any
  filename is still accepted)

### Bug fixes

- Fix missing `await` before main script execution, which caused post-hooks
  to run concurrently with the main script instead of after it
- Fix Ctrl+C propagation: signals now reliably kill the child process across
  multiple script executions; previously `ctrlc::set_handler` was called once
  per script invocation, causing a panic on the second call
- Fix CI blob build workflow: `ubuntu-20.04` and `macos-13` runners are
  retired; Windows `COPY` failed with a file-lock error when the Dart runtime
  had the existing DLL open

### New features

- **`(default)`** — Define a default script for a command group, executed
  when the group name is used without a sub-command

  ```yaml
  build:
    (default): flutter build apk
    web: flutter build web
  ```

- **Positional arguments** (`$1`, `$2`, …) — Inject individual command-line
  arguments into a script by position

  ```yaml
  greet: echo Hello $1
  # merry greet World  →  echo Hello World
  ```

- **`(workdir)`** — Run a script in a specific working directory

  ```yaml
  native:
    (workdir): packages/native
    (scripts): cargo build --release
  ```

- **Platform-specific scripts** (`(linux)`, `(macos)`, `(windows)`) —
  Select the right script automatically based on the current OS; falls back
  to `(scripts)` if no platform key matches

  ```yaml
  open:
    (linux): xdg-open .
    (macos): open .
    (windows): explorer .
  ```

- **`(aliases)`** — Define short aliases for frequently-used commands

  ```yaml
  install:
    (aliases): [i, in]
    (scripts): dart pub get
  # merry i  →  merry install
  ```

- **`(variables)`** / **`${VAR}`** — Define reusable variables scoped to the
  scripts map; environment variables are used as a fallback for unknown names

  ```yaml
  (variables):
    OUTPUT: build/release
  bundle: flutter build apk --output ${OUTPUT}
  ```

- **`merry ls --output=json`** — Machine-readable JSON output for tooling
  integration (e.g. VS Code extensions); use `--output=tree` (default) for
  the existing human-readable tree
  ```bash
  merry ls --output=json
  # {"name":"my_app","version":"1.0.0","scripts":[{"path":"build","commands":[...]},...]}
  ```

### Migrating from derry

1. Deactivate derry and install merry:
   ```bash
   dart pub global deactivate derry
   dart pub global activate merry
   ```
2. Replace all `derry` invocations with `merry` in scripts, CI pipelines,
   and documentation
3. Optionally rename `derry.yaml` → `merry.yaml` and update the `scripts:`
   value in `pubspec.yaml` — existing filenames continue to work unchanged
4. No changes to script definitions are required

## 1.5.0

- Add support for M1 Macs
- Blob sizes are now much smaller
- Opted-in to sound null-safety
- Rewrite most of the existing codes to be more concise and clearer, and also more performant by reducing io reads as much as possible and by caching a lot
- Use meaningful error codes with better error messages
- Rename `subcommands` to `references`
- Remove "execution type" which is useless and confusing
- Publishing is now done via GitHub Actions

## 1.4.3

- Bump version to correct `derry --version`

## 1.4.2

- Fix a bug by correctly passing extra arguments to parsed subcommands

## 1.4.1

- Add description option usage to README documentation

## 1.4.0

- Add description option which can now be used by `derry ls -d` command

## 1.3.0

- Update dependencies
- Refactor code with organized imports and typedefs according to new formatter rules

## 1.2.1

- Normalize absolute paths for `derry source` command
- Format old changelogs

## 1.2.0

- Enforce stricter linter rules and refactor according to it
- Support `pre` & `post` scripts
- Move native code into a separate directory

## 1.1.1

- Format according to `dartfmt` to get better pub score

## 1.1.0

- Scripts now return exit codes
- Remove `--slient` or `-s` option from `run` command
- Change info lines' styles
- Reduce exported API elements to only commands and version

## 1.0.5

- Update pub package description

## 1.0.4

- Refactor to not expose all APIs but only important ones so most library APIs will not be available
- Add more documentation comments

## 1.0.3

- Format error types in error messages to be uppercase

## 1.0.2

- Rename `derry update` command to `derry upgrade`
- Fix type casting error on extra arguments

## 1.0.1

- Format changelogs according to pub.dev

## 1.0.0

- Today I learned how versioning system actually works

## 0.1.4

- Derry now uses `lint` instead of `pedantic` as code linter & analyzer
- Code base is now formatted according to the `lint`'s rules
- Use `stdout` and `stderr` instead of `print`

## 0.1.3

- Add support for nested subcommands like `$generate:env` to run as `derry generate env`
- Add support for `derry update` command
- Sort output of `derry ls` tree
- Remove alias list

## 0.1.2

- Now `run` scripts can be used without using the `run` keyword. For example, `derry test` can be used instead of `derry run test` without explicit implementations, for all scripts
- Remove the old `build` and `test` alias implementations
- The derry commands no longer print the current directory on the script execution

## 0.1.1+1

- Update the pub link in README.md from `http` to `https` to get better pub score

## 0.1.1

- Refactor ffi directory to bindings directory
- Refactor usage lines to be all lowercase and with no period
- Adde `derry --version` option

## 0.1.0

- Add support for `derry source` command

## 0.0.9

- Add support for using subcommands with options/arguments/parameters

## 0.0.8+1

- Fix #20 `MultipleHandlers` Error caused by #12 fix

## 0.0.8

- Fix #12 Ctrl-C Error
- Add `-s` as abbrreviation for `--silent`

## 0.0.7+1

- Fix #14 error on not being able to use options caused by previous changes

## 0.0.7

- Add support for nested scripts
- Modify `Did you mean this?` check and `ls` commands to work well with nested scripts
- Breaking changes on `Advanced Configuration` API for compatibility with nested scripts

## 0.0.6

- Add `Did you mean this?` check by using `string-similarity` package
- Fix null infoLine error
- Fix command not found unhandled exceptions

## 0.0.5

- Add `derry ls` command
- Updat documentation

## 0.0.4

- Add support for `test` and `build` aliases
- Better and consistent error messages with an API

## 0.0.3+1

- Modify README to work correctly on pub.dev

## 0.0.3

- Add support for `--silent`
- Refactor Rust source code
- Start using derry for build
- Modify documentation

## 0.0.2

- Add support for subcommands

## 0.0.1

- Initial version, scaffolded by Stagehand
- Add support for list definitions
- Add support for configurable execution type
- Add support for win64, linux64, and (mac64)
- Add tests for helpers
