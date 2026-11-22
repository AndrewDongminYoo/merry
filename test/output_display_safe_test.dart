import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:merry/commands.dart';
import 'package:merry/error.dart';
import 'package:merry/utils.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// Collects what is written to `stdout` or `stderr` under [IOOverrides].
///
/// It reports no ANSI support, so the color helpers return plain text and the
/// captured output holds only what merry escaped.
class _CaptureStdout implements Stdout {
  final buffer = StringBuffer();

  @override
  bool get supportsAnsiEscapes => false;

  @override
  void write(Object? object) => buffer.write(object);

  @override
  void writeln([Object? object = '']) => buffer.writeln(object);

  @override
  Future<void> flush() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Runs [body] with `stdout` and `stderr` captured.
Future<({String out, String err})> _capture(Future<void> Function() body) async {
  final out = _CaptureStdout();
  final err = _CaptureStdout();
  await IOOverrides.runZoned(body, stdout: () => out, stderr: () => err);
  return (out: out.buffer.toString(), err: err.buffer.toString());
}

/// Runs `merry <args>` as a subprocess in [project], so the output is what a
/// user sees.
Future<ProcessResult> _runMerry(
  Directory project,
  List<String> args, {
  Map<String, String>? environment,
}) {
  return Process.run(
    Platform.resolvedExecutable,
    ['run', path.absolute('bin/merry.dart'), ...args],
    workingDirectory: project.path,
    environment: environment,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
}

void main() {
  group('formatCommandEcho', () {
    test(r'prints ${NAME} and $1 as written', () {
      expect(formatCommandEcho(r'deploy --token ${TOKEN} $1', const []), r'deploy --token ${TOKEN} $1');
    });

    test('escapes a control character', () {
      expect(formatCommandEcho('echo a\x1B[2Jb', const []), r'echo a\x1B[2Jb');
    });

    test('keeps line breaks and treats CRLF as one', () {
      expect(formatCommandEcho('first\nsecond\r\nthird', const []), 'first\nsecond\nthird');
      expect(formatCommandEcho('a\rb', const []), r'a\x0Db');
    });

    test('shows appended arguments quoted the way they run, escaped', () {
      final expected = Platform.isWindows ? r'echo one "two words" "x\x1By"' : r"echo one 'two words' 'x\x1By'";
      expect(formatCommandEcho('echo', const ['one', 'two words', 'x\x1By']), expected);
    });
  });

  group('ScriptsRegistry echo', () {
    test('prints the template before each command, not the substituted one', () async {
      final commands = <String>[];
      final registry = ScriptsRegistry(
        {
          '(variables)': {'TOKEN': 'registry-secret-value'},
          'deploy': [r'push ${TOKEN} $1', 'second'],
        },
        runCommand: (command) async {
          commands.add(command);
          return 0;
        },
      );

      final output = await _capture(() => registry.runScript('deploy', extra: ['arg1', 'extra']));

      expect(commands.first, contains('registry-secret-value'));
      expect(output.out, isNot(contains('registry-secret-value')));
      expect(output.out, '\$ push \${TOKEN} \$1 extra\n\n\$ second arg1 extra\n\n');
    });
  });

  group('handleError', () {
    test('escapes a script name and its suggestion', () async {
      final output = await _capture(() async {
        handleError(
          MerryError(
            type: ErrorCode.scriptNotDefined,
            body: {
              'script': 'buil\x1Bd',
              'suggestions': ['build\x1B'],
            },
          ),
        );
      });

      expect(output.err, contains(r'Unable to find script named "buil\x1Bd".'));
      expect(output.err, contains(r'build\x1B'));
      expect(output.err, isNot(contains('\x1B')));
    });

    test('escapes a path and a reference cycle', () async {
      final output = await _capture(() async {
        handleError(MerryError(type: ErrorCode.fileNotFound, body: {'path': 'a\x07.yaml'}));
        handleError(
          MerryError(
            type: ErrorCode.circularReference,
            body: {
              'cycle': ['a\x1B', 'a\x1B'],
            },
          ),
        );
      });

      expect(output.err, contains(r'File not found at "a\x07.yaml".'));
      expect(output.err, contains(r'a\x1B -> a\x1B'));
      expect(output.err, isNot(contains('\x1B')));
    });
  });

  group('init', () {
    late Directory project;

    setUp(() => project = Directory.systemTemp.createTempSync('merry-display-safe-init-'));
    tearDown(() => project.deleteSync(recursive: true));

    test('escapes the target file name in its messages', () async {
      // U+202E is a valid file-name character on every platform, and a terminal
      // would reorder the text after it.
      const target = 'scripts\u202E.yaml';
      File(path.join(project.path, 'pubspec.yaml')).writeAsStringSync('name: fixture\nscripts: "$target"\n');
      File(path.join(project.path, target)).writeAsStringSync('old: echo old\n');

      final questions = <String>[];
      final runner = CommandRunner<int>('merry', 'test')
        ..addCommand(
          InitCommand(
            projectPath: project.path,
            confirm: (question) {
              questions.add(question);
              return true;
            },
          ),
        );

      final output = await _capture(() => runner.run(['init']));

      expect(questions.single, r'scripts\u{202E}.yaml already exists. Replace its contents?');
      expect(output.out, contains(r'Wrote scripts\u{202E}.yaml.'));
      expect(output.out, isNot(contains('\u202E')));
    });
  });

  group('subprocess output', () {
    late Directory project;

    setUp(() => project = Directory.systemTemp.createTempSync('merry-display-safe-run-'));
    tearDown(() => project.deleteSync(recursive: true));

    void writePubspec(String scripts) {
      File(path.join(project.path, 'pubspec.yaml')).writeAsStringSync('name: fixture\nversion: 0.1.0\n$scripts');
    }

    test('the run banner and the error escape a script name', () async {
      writePubspec('scripts:\n  build: echo build\n');

      final result = await _runMerry(project, ['run', 'buil\x1Bd']);

      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains(r'> fixture@0.1.0 buil\x1Bd'));
      expect(result.stdout, isNot(contains('\x1B')));
      expect(result.stderr, contains(r'"buil\x1Bd"'));
    });

    test('source keeps a path with a control character when its output is piped', () async {
      // A script that captures `merry source` must get a name it can open.
      writePubspec('scripts: "a\\tb.yaml"\n');

      final result = await _runMerry(project, ['source', '--no-check']);

      expect(result.stdout, 'a\tb.yaml\n');
    });

    test('source escapes a control character only for a terminal', () {
      expect(sourceOutput('a\tb.yaml', toTerminal: true), r'a\x09b.yaml');
      expect(sourceOutput('a\tb.yaml', toTerminal: false), 'a\tb.yaml');
      expect(sourceOutput('tool/merry.yaml', toTerminal: true), 'tool/merry.yaml');
    });

    test('source prints a normal path unchanged', () async {
      writePubspec('scripts: tool/merry scripts.yaml\n');

      final result = await _runMerry(project, ['source', '--no-check']);

      expect(result.stdout, 'tool/merry scripts.yaml\n');
    });

    // This runs the checked-in native library. Until the blobs are rebuilt
    // from `native/`, the old library echoes the substituted command itself
    // and this test fails.
    test('the echo shows an environment reference, not its value', () async {
      const secret = 'merry-echo-secret-7f3a9c';
      // Neither command prints the value: `test -n` only checks it, and `rem`
      // ignores the rest of its line.
      final command = Platform.isWindows ? r'rem ${MERRY_ECHO_SECRET}' : r'test -n ${MERRY_ECHO_SECRET}';
      writePubspec('scripts:\n  check: $command\n');

      final result = await _runMerry(project, ['run', 'check'], environment: {'MERRY_ECHO_SECRET': secret});

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, isNot(contains(secret)));
      expect(const LineSplitter().convert(result.stdout as String), contains('\$ $command'));
    });
  });
}
