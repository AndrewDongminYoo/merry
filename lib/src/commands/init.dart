import 'dart:io' show Directory, File, FileMode, FileSystemEntity, FileSystemEntityType, Link, stdin, stdout;

import 'package:args/command_runner.dart';
import 'package:merry/error.dart' show ErrorCode, MerryError;
import 'package:merry/utils.dart' show JsonMap, Pubspec, pubspecFileName, rejectRest, scriptsKey;
import 'package:path/path.dart' as path;

/// Default file the generated scripts are written to.
const String defaultScriptsFileName = 'merry.yaml';

/// Asks the user a yes/no question. Injectable so `merry init` can be tested
/// without a terminal.
typedef Confirm = bool Function(String question);

bool _promptYesNo(String question) {
  stdout.write('$question [y/N] ');
  final answer = stdin.readLineSync()?.trim().toLowerCase();
  return answer == 'y' || answer == 'yes';
}

/// Whether [relative] resolves to an existing file or directory.
bool _exists(String projectPath, String relative) =>
    FileSystemEntity.typeSync(path.join(projectPath, relative)) != FileSystemEntityType.notFound;

/// How many links [_resolveWriteTarget] follows before calling it a loop. The
/// value only has to exceed any sane nesting depth; the OS enforces its own
/// limit once a write is actually attempted.
const int _maxLinkHops = 32;

/// Returns the path a write to [target] would land on, following symlinks the
/// way the filesystem does.
///
/// [File.resolveSymbolicLinks] cannot answer this: it throws when any component
/// is missing, which is exactly the case that matters — a dangling link, or a
/// file yet to be created under a linked directory. This walks to the deepest
/// existing ancestor, resolves that, and re-attaches the rest.
Future<String> _resolveWriteTarget(String target) async {
  var current = path.normalize(target);

  for (var hop = 0; hop < _maxLinkHops; hop++) {
    // A link is resolved by hand: the entity it names may not exist, and the
    // value it holds may itself be relative to the link's own directory.
    if (FileSystemEntity.isLinkSync(current)) {
      final destination = await Link(current).target();
      current = path.normalize(path.join(path.dirname(current), destination));
      continue;
    }

    // Walk up to something that exists, so the ancestors can be resolved.
    final segments = <String>[];
    var ancestor = current;
    while (!await FileSystemEntity.isDirectory(ancestor) && path.dirname(ancestor) != ancestor) {
      segments.insert(0, path.basename(ancestor));
      ancestor = path.dirname(ancestor);
    }

    final resolved = path.normalize(
      path.join(await Directory(ancestor).resolveSymbolicLinks(), path.joinAll(segments)),
    );
    // A resolved ancestor can expose a link deeper down, so keep going until the
    // path stops moving.
    if (resolved == current) return current;
    current = resolved;
  }

  throw MerryError(type: ErrorCode.invalidScripts);
}

/// Whether `dependencies` or `dev_dependencies` declares [package].
bool _dependsOn(JsonMap content, String package) {
  for (final key in const ['dependencies', 'dev_dependencies']) {
    final deps = content[key];
    if (deps is Map && deps.containsKey(package)) return true;
  }
  return false;
}

/// The `merry init` command
/// which writes a starter script file for the current project and links it
/// from `pubspec.yaml`.
///
/// The generated scripts are derived from what the project actually declares:
/// no `flutter build apk` without an `android/` directory, no `generate`
/// without `build_runner`.
///
/// A project that already defines its scripts inline in `pubspec.yaml` is left
/// untouched; one that points at a script file is only overwritten after the
/// user confirms.
class InitCommand extends Command<int> {
  InitCommand({String? projectPath, Confirm confirm = _promptYesNo})
    : projectPath = projectPath ?? Directory.current.path,
      _confirm = confirm;

  /// Directory holding the `pubspec.yaml` to initialize.
  final String projectPath;

  final Confirm _confirm;

  @override
  String get name => 'init';

  @override
  String get description => 'create a starter merry config for this project';

  @override
  Future<int> run() async {
    rejectRest(super.argResults!, usage);

    final pubspec = Pubspec(currentDirPath: projectPath);
    final content = await pubspec.getContent();
    final scripts = content[scriptsKey];

    final String target;
    if (!content.containsKey(scriptsKey)) {
      target = defaultScriptsFileName;
    } else if (scripts is String) {
      target = scripts;
    } else if (scripts is Map) {
      stdout.writeln('merry is already configured with inline scripts in $pubspecFileName. Nothing changed.');
      return 0;
    } else {
      // A `scripts:` key with no value lands here too — the config is
      // half-written and only the author can say what it should point at.
      throw MerryError(type: ErrorCode.invalidScripts);
    }

    // Mirror the containment check `Pubspec.getScripts` applies when reading, so
    // a `scripts: ../../elsewhere.yaml` cannot make init write outside the project.
    final scriptsPath = path.normalize(path.join(projectPath, target));
    if (!path.isWithin(projectPath, scriptsPath)) {
      throw MerryError(type: ErrorCode.invalidScripts);
    }

    // A directory (or anything else that is not a plain file) cannot be written
    // to; refuse it here instead of leaking a raw FileSystemException.
    final existingType = FileSystemEntity.typeSync(scriptsPath);
    if (existingType != FileSystemEntityType.notFound && existingType != FileSystemEntityType.file) {
      throw MerryError(type: ErrorCode.invalidScripts);
    }

    // Every check above is lexical, and a write follows symlinks. Decide where
    // the write would actually land before doing it: resolving both sides makes
    // a link out of the project, a link onto the manifest, and a `scripts:
    // pubspec.yaml` that names it directly all the same rejection.
    final resolvedProject = await Directory(projectPath).resolveSymbolicLinks();
    final resolvedScripts = await _resolveWriteTarget(scriptsPath);
    final resolvedPubspec = await _resolveWriteTarget(pubspec.filePath);
    if (!path.isWithin(resolvedProject, resolvedScripts) || path.equals(resolvedScripts, resolvedPubspec)) {
      throw MerryError(type: ErrorCode.invalidScripts);
    }

    final scriptsFile = File(scriptsPath);
    final linked = content.containsKey(scriptsKey);

    if (existingType == FileSystemEntityType.file && !_confirm('$target already exists. Replace its contents?')) {
      stdout.writeln('Nothing changed.');
      return 0;
    }

    await scriptsFile.parent.create(recursive: true);
    await scriptsFile.writeAsString(_buildTemplate(content, projectPath));

    if (!linked) await _linkPubspec(pubspec.filePath, target);

    // Load what was just written through the normal read path, so a broken
    // template or a botched pubspec edit fails here instead of on first use.
    await Pubspec(currentDirPath: projectPath).getScripts();

    stdout.writeln(
      linked ? 'Wrote $target.' : 'Wrote $target and linked it from $pubspecFileName.',
    );
    stdout.writeln('Run `merry ls` to see the available scripts.');
    return 0;
  }

  /// Appends `scripts: <target>` as a new top-level key.
  ///
  /// Appending rather than re-serializing keeps every comment and blank line in
  /// `pubspec.yaml` exactly where the author put it. It is only ever called when
  /// the key is absent, since a duplicate top-level key is invalid YAML.
  Future<void> _linkPubspec(String pubspecPath, String target) async {
    final file = File(pubspecPath);
    final content = await file.readAsString();
    final entry = '$scriptsKey: $target\n';

    // A `...` terminator ends the document, so a key appended after it is not
    // part of the manifest at all. Put the key in front of the terminator, and
    // of whatever trailing comments sit above it.
    final lines = content.split('\n');
    var insertAt = lines.length;
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line == '...') insertAt = i;
      break;
    }

    if (insertAt < lines.length) {
      // `join` supplies the line break, so insert the key without its own.
      lines.insert(insertAt, entry.trimRight());
      await file.writeAsString(lines.join('\n'));
      return;
    }

    // Without this a file that does not end in a newline would get the new key
    // glued onto its last line.
    final separator = content.endsWith('\n') ? '\n' : '\n\n';
    await file.writeAsString('$separator$entry', mode: FileMode.append);
  }
}

/// Builds the starter script file for the project described by [content].
String _buildTemplate(JsonMap content, String projectPath) {
  bool has(String relative) => _exists(projectPath, relative);

  final isFlutter = _dependsOn(content, 'flutter');
  final tool = isFlutter ? 'flutter' : 'dart';
  final flutterConfig = content['flutter'];

  // A plugin declares `flutter: plugin:` and is never runnable itself, whatever
  // its lib/ happens to contain — `lib/main.dart` in a plugin is just a library
  // file with a common name. Its platform directories hold the native
  // implementation, not an app to build.
  final isPlugin = flutterConfig is Map && flutterConfig.containsKey('plugin');
  final isApp = isFlutter && !isPlugin && has('lib/main.dart');

  final buffer = StringBuffer('# Generated by `merry init`. Safe to edit.\n');

  if (isApp) {
    buffer.write('''

dev:
  (description): Run the app.
  (scripts): flutter run
''');
  } else if (isFlutter && has('example/pubspec.yaml')) {
    // A plugin or package is not runnable itself; its example app is.
    buffer.write('''

dev:
  (description): Run the example app.
  (workdir): example
  (scripts): flutter run
''');
  } else if (!isFlutter && has('bin/${content['name']}.dart')) {
    // A bare `dart run` resolves `bin/<package name>.dart` and nothing else, so
    // it is only worth generating when that exact file is there.
    buffer.write('''

dev:
  (description): Run the executable.
  (scripts): dart run
''');
  }

  buffer.write('''

analyze:
  (description): Run static analysis.
  (scripts): $tool analyze

format:
  (description): Format Dart sources.
  (default): dart format .

  check:
    (description): Fail when sources are not formatted.
    (scripts): dart format --output=none --set-exit-if-changed .
''');

  final hasTests = has('test');
  if (hasTests) {
    // `flutter test --coverage` writes coverage/lcov.info on its own; the Dart
    // runner needs to be told where to put it.
    final coverage = isFlutter ? 'flutter test --coverage' : 'dart test --coverage-path=coverage/lcov.info';
    buffer.write('''

test:
  (description): Run the tests.
  (default): $tool test

  coverage:
    (description): Run the tests and write coverage/lcov.info.
    (scripts): $coverage
''');
  }

  if (_dependsOn(content, 'build_runner')) {
    buffer.write('''

generate:
  (description): Run code generation.
  (scripts): dart run build_runner build --delete-conflicting-outputs
''');
  }

  if (isFlutter && (has('l10n.yaml') || (flutterConfig is Map && flutterConfig['generate'] == true))) {
    buffer.write('''

l10n:
  (description): Regenerate localizations.
  (scripts): flutter gen-l10n
''');
  }

  // Only an app builds artifacts, and only for the platforms it actually has.
  if (isApp) {
    const targets = <String, List<String>>{
      'android': ['apk: flutter build apk --release', 'aab: flutter build appbundle --release'],
      'ios': ['ipa: flutter build ipa --release'],
      'web': ['web: flutter build web --release'],
      'macos': ['macos: flutter build macos --release'],
      'windows': ['windows: flutter build windows --release'],
      'linux': ['linux: flutter build linux --release'],
    };
    final entries = [
      for (final entry in targets.entries)
        if (has(entry.key)) ...entry.value,
    ];
    if (entries.isNotEmpty) {
      // No `(default)`: which artifact a project ships is not something that
      // can be read off the directory listing.
      buffer.write('\nbuild:\n');
      for (final entry in entries) {
        buffer.write('  $entry\n');
      }
    }
  }

  buffer.write(r'''

check:
  (description): Run the local quality gates.
  (execution): once
  (scripts):
    - $format:check
    - $analyze
''');
  if (hasTests) buffer.write('    - \$test\n');

  return buffer.toString();
}
