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
      'merry: native',
      'merry: present',
      'merry: ship',
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

  test('ls --output=json names a nested script by its full path and carries optional fields', () async {
    final output = await runLs('json');

    expect(output['name'], 'fixture_project');
    expect(output['version'], '0.1.0');

    final byName = {
      for (final script in (output['scripts'] as List).cast<Map<String, dynamic>>()) script['name'] as String: script,
    };

    // a nested script is named by its whole path, not by its leaf
    expect(byName['build debug']!['commands'], ['echo build-debug']);

    // `(workdir)` and a non-default `(execution)` are reported, and both keys
    // stay out of a definition that does not set them
    expect(byName['native']!['workdir'], 'native');
    expect(byName['ship']!['execution'], 'once');
    expect(byName['test']!.containsKey('workdir'), isFalse);
    expect(byName['test']!.containsKey('execution'), isFalse);
  });

  test('ls --output=json reports hooks from both directions', () async {
    final output = await runLs('json');
    final byName = {
      for (final script in (output['scripts'] as List).cast<Map<String, dynamic>>()) script['name'] as String: script,
    };

    expect(byName['test']!['hooks'], {'pre': 'pretest', 'post': 'posttest'});
    expect(byName['pretest']!['hook_for'], 'test');
    expect(byName['posttest']!['hook_for'], 'test');

    // `present` starts with `pre`, but no `sent` script exists to hook onto
    expect(byName['present']!.containsKey('hook_for'), isFalse);
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
