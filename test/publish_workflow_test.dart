import 'dart:io' show File;

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('publish workflow accepts only semantic version tags', () {
    final workflow = File('.github/workflows/publish.yml').readAsStringSync();

    expect(workflow, contains(r'[[ "$GITHUB_REF_NAME" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]'));
  });

  test('publish credentials are isolated from verification steps', () {
    final workflowFile = File('.github/workflows/publish.yml');
    final workflow = loadYaml(workflowFile.readAsStringSync()) as YamlMap;
    final jobs = workflow['jobs'] as YamlMap;
    final testJob = jobs['test'] as YamlMap;
    final publishJob = jobs['publish'] as YamlMap;

    final testPermissions = testJob['permissions'] as YamlMap?;
    expect(testPermissions?['id-token'], isNot('write'));
    expect(publishJob['needs'], 'test');
    expect(publishJob['permissions'], containsPair('id-token', 'write'));

    final publishSteps = publishJob['steps'] as YamlList;
    expect(
      publishSteps.whereType<YamlMap>().map((step) => step['run']),
      isNot(contains(anyOf('dart pub get', 'dart test'))),
    );

    final actionPattern = RegExp(r'^[^@]+@[0-9a-f]{40}$');
    for (final job in jobs.values.whereType<YamlMap>()) {
      final steps = job['steps'] as YamlList;
      for (final step in steps.whereType<YamlMap>()) {
        if (step['uses'] case final String action) {
          expect(action, matches(actionPattern));
        }
      }
    }
  });
}
