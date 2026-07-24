import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('only the PR job has repository write permissions', () {
    final workflow =
        loadYaml(
              File('.github/workflows/build.yml').readAsStringSync(),
            )
            as YamlMap;
    final permissions = workflow['permissions'] as YamlMap;
    final jobs = workflow['jobs'] as YamlMap;
    final makePr = jobs['make_pr'] as YamlMap;

    expect(permissions['contents'], 'read');
    expect(permissions['pull-requests'], isNull);
    expect(makePr['permissions'], {
      'contents': 'write',
      'pull-requests': 'write',
    });
  });

  test('build jobs do not persist checkout credentials', () {
    final workflow =
        loadYaml(
              File('.github/workflows/build.yml').readAsStringSync(),
            )
            as YamlMap;
    final jobs = workflow['jobs'] as YamlMap;

    for (final entry in jobs.entries.where((entry) => entry.key != 'make_pr')) {
      final job = entry.value as YamlMap;
      final steps = job['steps'] as YamlList;
      // Matched by prefix: the ref is a pinned commit SHA, not a tag.
      final checkout = steps.cast<YamlMap>().singleWhere(
        (step) => step['uses'].toString().startsWith('actions/checkout@'),
      );

      expect(
        (checkout['with'] as YamlMap?)?['persist-credentials'],
        isFalse,
        reason: '${entry.key} must not retain a repository credential',
      );
    }
  });
}
