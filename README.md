# Merry

Merry is a script manager for Dart.

> **Merry** is a maintained fork of [derry](https://pub.dev/packages/derry) by [Frenco](https://github.com/frencojobs).
> All script definitions are compatible — only the CLI command changes from `derry` to `merry`.
> See [Migrating from derry](#migrating-from-derry) below.

## Overview

Merry helps you define shortcut scripts, and save you from having to type very long and forgettable long lines of scripts, again and again.

Instead of running this every time,

```bash
dart run build_runner build --delete-conflicting-outputs
```

Add this to `pubspec.yaml`,

```yaml
scripts:
  build: dart run build_runner build --delete-conflicting-outputs
```

and run

```bash
merry build
```

<br>

## Installation

Install merry as a global dependency from [pub.dev](https://pub.dev) like this.

```bash
dart pub global activate merry
```

Then use merry to run a command from the current dart/flutter project.

```bash
merry [script]
```

<br>

## Usage

When called, merry will look for a `pubspec.yaml` file in the current directory, and will throw an error if it doesn't exist. The scripts can be declared within the `scripts` node of the `pubspec.yaml` file.

```yaml
scripts:
  build: dart run build_runner build
```

```bash
merry build
# or even with additional arguments
merry build -- --delete-conflicting-outputs
```

<br>

## API Documentation

**Use definition file**

Scripts can be configured just inside the `pubspec.yaml` file or within a separate file. When using a separate file to configure scripts, pass the file name as the value of the `scripts` node in the `pubspec.yaml` file.

```yaml
# pubspec.yaml
scripts: merry.yaml
```

```yaml
# merry.yaml
build: dart run build_runner build
```

**Use scripts as List**

A script can either be a single string or a list of strings. If it is a list, the strings inside of the list will be executed synchronously in the given order of the list.

```yaml
build:
  - dart test
  - echo "test completed"
  - dart run build_runner build
```

**Nested scripts**

Scripts can be nested as the user needed. For example, you can use them to use different implementations of the build script based on operating system.

```yaml
build:
  windows:
    - echo 0 # do something
  mac:
    - echo 1 # do something else
```

And you can use them by calling `merry build windows` on windows and `merry build mac` on macOS.

**Pre and post scripts**

With pre & post scripts, you can easily define a script to run before and after a specific script without hassling with references. Merry automatically understands them from the names.

```yaml
prepublish:
  - cargo build && copy target blob
  - dart test
publish:
  - dart pub publish
postpublish:
  - rm -rf blob
```

**Configure script descriptions**

You can add a string to `(description)` option, which can be useful when viewing through a list of available via `merry ls -d` command. When you are using `(description)` field, you must use `(script)` field to define scripts.

```yaml
build:
  (description): script to be called after every update to x.dart file
  (scripts):
    - cat generated.txt
    - dart run build_runner build
```

**Configure multiline scripts**

Note that in the list of scripts, executions will happen in separate processes. You can use `&&` to execute multiple scripts in the same process.

```yaml
# > or | can be used to define multiline strings, this is a standard YAML syntax
build: >
  cat generated.txt &&
  dart run build_runner build

# the second line won't be called if generated.txt does not exist
```

**Use references**

When defining scripts, you can reference to other scripts via `$` syntax. These references to scripts won't be executed with a separate merry process. For example,

```yaml
test:
  - dart run test
  - echo "test completed"
build:
  - $test # instead of using merry test
  - $test --ignored # even with arguments
  - flutter build
generate:
  env:
    - echo env
release:
  - $generate:env # use nested references via :
  - $build
```

`merry test` will spawn a new merry process to execute, while references won't, reducing the time took to run dart code, and spawn that process.
But note that references will take a whole line of script. For example, you have to give a separate line for a subcommand, you can't use them together with other scripts or sandwiched in a string.

**Platform-specific scripts**

Use `(linux)`, `(macos)`, or `(windows)` keys to define platform-dependent scripts. The correct one is selected automatically at runtime; `(scripts)` is used as a fallback when no key matches the current OS.

```yaml
open:
  (linux): xdg-open .
  (macos): open .
  (windows): explorer .
```

**Default script for a command group**

When a command group is called without a sub-command, the `(default)` script is executed.

```yaml
build:
  (default): flutter build apk
  web: flutter build web
```

```bash
merry build      # runs flutter build apk
merry build web  # runs flutter build web
```

**Positional arguments**

Use `$1`, `$2`, etc. to inject individual arguments from the command line into a script. Remaining arguments not consumed by positional tokens are appended at the end.

```yaml
greet: echo Hello $1
run: dart run $1 $2
```

```bash
merry greet World   # → echo Hello World
merry run bin/main  # → dart run bin/main
```

**Working directory**

Use `(workdir)` to run a script inside a specific directory. The path is relative to the project root.

```yaml
native:
  (workdir): packages/native
  (scripts): cargo build --release
```

**Command aliases**

Use `(aliases)` to define short aliases for a command. Aliases can be a single string or a list of strings.

```yaml
install:
  (aliases): [i, in]
  (scripts): dart pub get
```

```bash
merry i   # → merry install
merry in  # → merry install
```

**Variable substitution**

Define reusable variables in a `(variables)` section at the top level or inside any command group. Reference them with `${VAR}` syntax in scripts. Environment variables are used as a fallback for undefined names.

```yaml
(variables):
  OUTPUT: build/release
  MODE: release

bundle: flutter build apk --output ${OUTPUT} --${MODE}
```

**List available scripts**

Use this command to see what scripts are available in the current configuration.

```bash
merry ls # --description or -d to output descriptions
```

**Check the location of the merry scripts**

Use this command to see the location (both absolute and relative) path of the merry script file. You can also use this to check if the scripts are correctly formatted or the location is correct.

```bash
merry source # --absolute or -a to show absolute path
```

**Upgrade merry**

```bash
dart pub global activate merry # or
merry upgrade # will run `dart pub global activate merry`
```

<br>

## Migrating from derry

1. Deactivate derry and install merry:
   ```bash
   dart pub global deactivate derry
   dart pub global activate merry
   ```
2. Replace all `derry` invocations with `merry`
3. Optionally rename `derry.yaml` → `merry.yaml` and update the `scripts:` value in `pubspec.yaml`
4. No changes to script definitions are required — the format is fully compatible

<br>

## Why & How

Honestly, I needed it. It was easy to make, though I had a hard time implementing the script execution. Since Dart's `Process` isn't good at executing system commands, I used Rust with the help of _Foreign Function Interfaces_. For execution, currently `cmd` is used for Windows and `bash` is used for Linux and Mac.

<br>

## Currently Supported Platforms

64bit Linux, Windows, and Mac are currently supported.
