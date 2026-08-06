import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:merry/commands.dart';
import 'package:merry/error.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// Runs `merry init` against [projectPath] and returns its exit code.
Future<int> runInit(String projectPath, {bool confirm = false}) async {
  final runner = CommandRunner<int>('merry', 'test')
    ..addCommand(InitCommand(projectPath: projectPath, confirm: (_) => confirm));
  return await runner.run(['init']) ?? 0;
}

void main() {
  late Directory project;

  String read(String relative) => File(path.join(project.path, relative)).readAsStringSync();
  void write(String relative, String content) {
    final file = File(path.join(project.path, relative))..parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  setUp(() => project = Directory.systemTemp.createTempSync('merry_init_test'));
  tearDown(() => project.deleteSync(recursive: true));

  test('links a generated merry.yaml and keeps pubspec comments intact', () async {
    write('pubspec.yaml', '''
name: demo
# a comment worth keeping

dependencies:
  flutter:
    sdk: flutter
''');
    write('lib/main.dart', 'void main() {}');

    expect(await runInit(project.path), 0);

    expect(read('pubspec.yaml'), '''
name: demo
# a comment worth keeping

dependencies:
  flutter:
    sdk: flutter

scripts: merry.yaml
''');
    expect(read('merry.yaml'), contains('flutter run'));
  });

  test('appends a blank line when pubspec has no trailing newline', () async {
    write('pubspec.yaml', 'name: demo');

    expect(await runInit(project.path), 0);

    expect(read('pubspec.yaml'), 'name: demo\n\nscripts: merry.yaml\n');
  });

  test('generates only the platforms and tools the project has', () async {
    write('pubspec.yaml', '''
name: demo
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  build_runner: ^2.13.1
''');
    write('lib/main.dart', 'void main() {}');
    write('test/widget_test.dart', '');
    Directory(path.join(project.path, 'android')).createSync();
    Directory(path.join(project.path, 'web')).createSync();

    await runInit(project.path);
    final scripts = read('merry.yaml');

    expect(scripts, contains('flutter build apk --release'));
    expect(scripts, contains('flutter build web --release'));
    expect(scripts, isNot(contains('flutter build ipa')));
    expect(scripts, isNot(contains('flutter build macos')));
    expect(scripts, contains('dart run build_runner build'));
    expect(scripts, contains('flutter test --coverage'));
  });

  test('a Dart package gets dart commands and no build targets', () async {
    write('pubspec.yaml', 'name: demo\n');
    write('bin/demo.dart', 'void main() {}');
    write('test/demo_test.dart', '');
    Directory(path.join(project.path, 'android')).createSync();

    await runInit(project.path);
    final scripts = read('merry.yaml');

    expect(scripts, contains('dart analyze'));
    expect(scripts, contains('dart test --coverage-path=coverage/lcov.info'));
    expect(scripts, contains('dart run'));
    expect(scripts, isNot(contains('flutter')));
    expect(scripts, isNot(contains('build:')));
  });

  test('skips dev when bin holds no entrypoint named after the package', () async {
    // A bare `dart run` only resolves `bin/<package name>.dart`.
    write('pubspec.yaml', 'name: demo\n');
    write('bin/something_else.dart', 'void main() {}');

    await runInit(project.path);

    expect(read('merry.yaml'), isNot(contains('dev:')));
  });

  test('skips test scripts when the project has no test directory', () async {
    write('pubspec.yaml', 'name: demo\n');

    await runInit(project.path);
    final scripts = read('merry.yaml');

    expect(scripts, isNot(contains('test:')));
    expect(scripts, isNot(contains(r'- $test')));
  });

  test('leaves an inline scripts map untouched', () async {
    const pubspec = 'name: demo\nscripts:\n  build: dart compile exe bin/demo.dart\n';
    write('pubspec.yaml', pubspec);

    expect(await runInit(project.path), 0);

    expect(read('pubspec.yaml'), pubspec);
    expect(File(path.join(project.path, 'merry.yaml')).existsSync(), isFalse);
  });

  test('writes to the configured path without touching pubspec', () async {
    const pubspec = 'name: demo\nscripts: tool/scripts.yaml\n';
    write('pubspec.yaml', pubspec);

    expect(await runInit(project.path), 0);

    expect(read('pubspec.yaml'), pubspec);
    expect(read('tool/scripts.yaml'), contains('dart analyze'));
  });

  test('keeps an existing script file when the prompt is declined', () async {
    write('pubspec.yaml', 'name: demo\nscripts: merry.yaml\n');
    write('merry.yaml', 'mine: echo hello\n');

    expect(await runInit(project.path), 0);

    expect(read('merry.yaml'), 'mine: echo hello\n');
  });

  test('replaces an existing script file once confirmed', () async {
    write('pubspec.yaml', 'name: demo\nscripts: merry.yaml\n');
    write('merry.yaml', 'mine: echo hello\n');

    expect(await runInit(project.path, confirm: true), 0);

    expect(read('merry.yaml'), contains('dart analyze'));
  });

  test('rejects a scripts path pointing outside the project', () async {
    write('pubspec.yaml', 'name: demo\nscripts: ../escape.yaml\n');

    await expectLater(
      runInit(project.path),
      throwsA(isA<MerryError>().having((e) => e.type, 'type', ErrorCode.invalidScripts)),
    );
    expect(File(path.join(project.path, '../escape.yaml')).existsSync(), isFalse);
  });

  test('refuses to overwrite pubspec.yaml itself', () async {
    // `scripts: pubspec.yaml` reads back as an inline map, so treating it as a
    // file target would replace the manifest with a script file.
    const pubspec = 'name: demo\nscripts: pubspec.yaml\n';
    write('pubspec.yaml', pubspec);

    await expectLater(
      runInit(project.path, confirm: true),
      throwsA(isA<MerryError>().having((e) => e.type, 'type', ErrorCode.invalidScripts)),
    );
    expect(read('pubspec.yaml'), pubspec);
  });

  test('rejects a scripts path that is a directory', () async {
    write('pubspec.yaml', 'name: demo\nscripts: tool\n');
    Directory(path.join(project.path, 'tool')).createSync();

    await expectLater(
      runInit(project.path, confirm: true),
      throwsA(isA<MerryError>().having((e) => e.type, 'type', ErrorCode.invalidScripts)),
    );
  });

  test('refuses to write through a dangling symlink escaping the project', () async {
    // The link resolves to nothing yet, so the target reads as `notFound` — but
    // the write would still follow it and create the file outside the project.
    final outside = File(path.join(project.parent.path, 'merry_init_dangling.yaml'));
    addTearDown(() => outside.existsSync() ? outside.deleteSync() : null);

    write('pubspec.yaml', 'name: demo\nscripts: link.yaml\n');
    Link(path.join(project.path, 'link.yaml')).createSync(outside.path);

    await expectLater(
      runInit(project.path, confirm: true),
      throwsA(isA<MerryError>().having((e) => e.type, 'type', ErrorCode.invalidScripts)),
    );
    expect(outside.existsSync(), isFalse);
  });

  test('refuses to write beneath a directory symlink escaping the project', () async {
    final outside = Directory(path.join(project.parent.path, 'merry_init_outdir'))..createSync();
    addTearDown(() => outside.existsSync() ? outside.deleteSync(recursive: true) : null);

    write('pubspec.yaml', 'name: demo\nscripts: linked/scripts.yaml\n');
    Link(path.join(project.path, 'linked')).createSync(outside.path);

    await expectLater(
      runInit(project.path, confirm: true),
      throwsA(isA<MerryError>().having((e) => e.type, 'type', ErrorCode.invalidScripts)),
    );
    expect(outside.listSync(), isEmpty);
  });

  test('refuses a scripts symlink resolving onto a symlinked pubspec', () async {
    // Both paths reach the same manifest; only resolving each side reveals it.
    write('real_pubspec.yaml', 'name: demo\nscripts: link.yaml\n');
    Link(path.join(project.path, 'pubspec.yaml')).createSync(path.join(project.path, 'real_pubspec.yaml'));
    Link(path.join(project.path, 'link.yaml')).createSync(path.join(project.path, 'real_pubspec.yaml'));

    await expectLater(
      runInit(project.path, confirm: true),
      throwsA(isA<MerryError>().having((e) => e.type, 'type', ErrorCode.invalidScripts)),
    );
    expect(read('real_pubspec.yaml'), 'name: demo\nscripts: link.yaml\n');
  });

  test('inserts the scripts key before a YAML document terminator', () async {
    write('pubspec.yaml', 'name: demo\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n...\n');

    expect(await runInit(project.path), 0);

    expect(read('pubspec.yaml'), 'name: demo\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\nscripts: merry.yaml\n...\n');
  });

  test('refuses a script file hard-linked to the manifest', () async {
    // One inode, two names: no amount of path resolution tells them apart, so
    // writing through either would truncate the manifest.
    write('pubspec.yaml', 'name: demo\nscripts: hard.yaml\n');
    Process.runSync('ln', [path.join(project.path, 'pubspec.yaml'), path.join(project.path, 'hard.yaml')]);

    await expectLater(
      runInit(project.path, confirm: true),
      throwsA(isA<MerryError>().having((e) => e.type, 'type', ErrorCode.invalidScripts)),
    );
    expect(read('pubspec.yaml'), 'name: demo\nscripts: hard.yaml\n');
  });

  test('inserts the scripts key before a commented document terminator', () async {
    write('pubspec.yaml', 'name: demo\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n... # end\n');

    expect(await runInit(project.path), 0);

    expect(
      read('pubspec.yaml'),
      'name: demo\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\nscripts: merry.yaml\n... # end\n',
    );
  });

  test('treats a line merely starting with dots as content', () async {
    // The last line starts with `...` but is a block scalar's content, not a
    // terminator, so the key still belongs at the end of the file.
    write('pubspec.yaml', 'name: demo\ndescription: |\n  ...trailing off\n');

    expect(await runInit(project.path), 0);

    expect(read('pubspec.yaml'), 'name: demo\ndescription: |\n  ...trailing off\n\nscripts: merry.yaml\n');
  });

  test('a plugin with a lib/main.dart is still not treated as an app', () async {
    write('pubspec.yaml', '''
name: demo
dependencies:
  flutter:
    sdk: flutter
flutter:
  plugin:
    platforms:
      android:
        package: com.example
''');
    write('lib/main.dart', 'const answer = 42;');
    write('example/pubspec.yaml', 'name: demo_example\n');
    Directory(path.join(project.path, 'android')).createSync();

    await runInit(project.path);
    final scripts = read('merry.yaml');

    expect(scripts, contains('(workdir): example'));
    expect(scripts, isNot(contains('flutter build')));
  });

  test('refuses to write through a symlink escaping the project', () async {
    final outside = File(path.join(project.parent.path, 'merry_init_outside.yaml'))..writeAsStringSync('keep me\n');
    addTearDown(() => outside.existsSync() ? outside.deleteSync() : null);

    write('pubspec.yaml', 'name: demo\nscripts: link.yaml\n');
    Link(path.join(project.path, 'link.yaml')).createSync(outside.path);

    await expectLater(
      runInit(project.path, confirm: true),
      throwsA(isA<MerryError>().having((e) => e.type, 'type', ErrorCode.invalidScripts)),
    );
    expect(outside.readAsStringSync(), 'keep me\n');
  });

  test('rejects a scripts key with no value instead of writing a duplicate', () async {
    write('pubspec.yaml', 'name: demo\nscripts:\n');

    await expectLater(
      runInit(project.path),
      throwsA(isA<MerryError>().having((e) => e.type, 'type', ErrorCode.invalidScripts)),
    );
    expect(read('pubspec.yaml'), 'name: demo\nscripts:\n');
  });
}
