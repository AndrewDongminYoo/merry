import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// Runs `merry run <args>` as a subprocess, so the command reaches the real
/// native blob and the platform shell (`sh -c` or `cmd /C`).
Future<ProcessResult> runMerry(
  Directory project,
  List<String> args, {
  Map<String, String>? environment,
}) {
  return Process.run(
    Platform.resolvedExecutable,
    ['run', path.absolute('bin/merry.dart'), 'run', ...args],
    workingDirectory: project.path,
    environment: environment,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
}

void main() {
  late Directory project;
  late File marker;

  // Each payload creates the marker file `pwned` in the project directory if
  // the shell executes it. The relative name keeps `\` and spaces of a temp
  // path out of the command.
  //
  // [barePayload] runs when it is spliced without quotes. It chains with `;`
  // in sh, because `&` would put the write in the background and let the test
  // check the marker before it exists. cmd has no `;` separator, so it uses `&`.
  final barePayload = Platform.isWindows ? 'x & echo pwned > pwned & echo y' : 'x; echo pwned > pwned; echo y';
  // [quotedPayload] runs when merry wraps it in `"..."` on Windows: the `"`
  // ends the quoted word in cmd, which honors no backslash escape.
  const quotedPayload = 'x" & echo pwned > pwned & echo "y';

  setUp(() {
    project = Directory.systemTemp.createTempSync('merry-inert-run-test-');
    marker = File(path.join(project.path, 'pwned'));
    // The positional fixture surrounds `$1` with the quote that shellQuote adds
    // on each platform, so the two quotes cancel out and the value is bare.
    final positional = Platform.isWindows ? r'echo "$1"' : r"echo '$1'";
    File(path.join(project.path, 'pubspec.yaml')).writeAsStringSync(
      'name: inert_fixture\n'
      'version: 0.1.0\n'
      'scripts:\n'
      '  positional: $positional\n'
      '  appended: echo\n'
      r'  fallback: echo ${MERRY_INERT_PAYLOAD}'
      '\n',
    );
  });

  tearDown(() => project.deleteSync(recursive: true));

  void expectRefused(ProcessResult result, String describe) {
    // Checked first, so a run without the guard fails on the marker.
    expect(marker.existsSync(), isFalse, reason: 'the payload reached the shell');
    expect(result.exitCode, isNot(0), reason: '${result.stdout}');
    expect(result.stderr, contains('Refusing to run: $describe'));
  }

  test('a positional argument with shell syntax does not reach the shell', () async {
    final result = await runMerry(project, ['positional', '--', barePayload]);
    expectRefused(result, r'positional argument $1');
  });

  test('an environment fallback value with shell syntax does not reach the shell', () async {
    final result = await runMerry(
      project,
      ['fallback'],
      environment: {'MERRY_INERT_PAYLOAD': barePayload},
    );
    expectRefused(result, r'environment variable ${MERRY_INERT_PAYLOAD}');
  });

  test('an appended argument with shell syntax does not reach the shell', () async {
    final result = await runMerry(project, ['appended', '--', quotedPayload]);

    if (Platform.isWindows) {
      expectRefused(result, 'appended argument 1');
    } else {
      // POSIX single-quotes the appended value, so it runs as plain text.
      expect(marker.existsSync(), isFalse, reason: 'the payload reached the shell');
      expect(result.exitCode, 0, reason: '${result.stderr}');
      // merry echoes the command with the argument (`$ echo ...`) before it
      // runs it, so a substring match would pass on the echo alone. The child's `echo`
      // prints the argument on a line of its own only if it arrived intact.
      expect(const LineSplitter().convert(result.stdout as String), contains(quotedPayload));
    }
  });
}
