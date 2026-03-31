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
