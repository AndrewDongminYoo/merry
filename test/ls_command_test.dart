import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// Runs `merry ls` against the fixture project, whose script set covers
/// hooks, nested names and references.
Future<Map<String, dynamic>> runLs(String format) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    ['run', path.absolute('bin/merry.dart'), 'ls', '--output=$format'],
    workingDirectory: path.absolute('test', 'fixtures', 'scripts_project'),
  );

  expect(result.exitCode, 0, reason: '${result.stderr}');
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

void main() {
  test('ls --output=tasks lists every script except pre/post hooks', () async {
    final output = await runLs('tasks');
    final labels = (output['tasks'] as List).map((task) => (task as Map)['label']).toList();

    // `pretest` and `posttest` are hooks of `test`, while `present` has no
    // `sent` script to hook onto and therefore stays on the list.
    expect(labels, [
      'merry: build debug',
      'merry: build release',
      'merry: ls',
      'merry: present',
      'merry: test',
    ]);
    expect(output['version'], '2.0.0');
  });

  test('a task runs its script through the local merry executable', () async {
    final output = await runLs('tasks');
    final tasks = (output['tasks'] as List).cast<Map<String, dynamic>>();

    // the space of a nested name survives because it is a single argument
    expect(tasks.firstWhere((task) => task['label'] == 'merry: build debug'), {
      'label': 'merry: build debug',
      'type': 'process',
      'command': 'dart',
      'args': ['run', 'merry:merry', 'run', 'build debug'],
      'problemMatcher': <String>[],
    });

    // `(description)` shows up under the label in the VS Code task picker
    expect(tasks.firstWhere((task) => task['label'] == 'merry: test')['detail'], 'run the suite');
  });

  test('a script named after a merry subcommand still runs the script', () async {
    final output = await runLs('tasks');
    final tasks = (output['tasks'] as List).cast<Map<String, dynamic>>();

    // `merry ls` would list the scripts instead of running the one named `ls`,
    // because a name only falls through to `run` when no subcommand claims it
    expect(
      tasks.firstWhere((task) => task['label'] == 'merry: ls')['args'],
      ['run', 'merry:merry', 'run', 'ls'],
    );
  });
}
