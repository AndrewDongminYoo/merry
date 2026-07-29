import 'dart:io' show Directory, File;

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  // build.yml and publish.yml each have their own assertions, but verify.yml
  // had none, so its checkout silently kept a credential and an unpinned tag.
  // This sweeps every workflow instead, so a new one cannot miss the rule.
  test('every workflow checkout is pinned and drops its credential', () {
    final workflows = Directory('.github/workflows')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.yml'));

    expect(workflows, isNotEmpty, reason: 'no workflows found to check');

    final pinnedToSha = RegExp(r'^[^@]+@[0-9a-f]{40}$');
    for (final file in workflows) {
      final jobs = (loadYaml(file.readAsStringSync()) as YamlMap)['jobs'] as YamlMap;

      for (final entry in jobs.entries) {
        final steps = (entry.value as YamlMap)['steps'] as YamlList;
        final where = '${file.path} [${entry.key}]';

        for (final step in steps.whereType<YamlMap>()) {
          if (step['uses'] case final String action when action.startsWith('actions/checkout@')) {
            expect(action, matches(pinnedToSha), reason: '$where must pin checkout to a commit SHA');
            expect(
              (step['with'] as YamlMap?)?['persist-credentials'],
              isFalse,
              reason: '$where must not retain a repository credential',
            );
          }
        }
      }
    }
  });
}
