import 'dart:io' show File;

import 'package:merry/version.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  // `lib/src/version.dart` is written by build_version from `pubspec.yaml`, so
  // a release that bumps the manifest without re-running build_runner ships a
  // binary whose `--version` lies. This runs in publish.yml's test job, which
  // gates the tag, so the drift is caught before it reaches pub.dev.
  test('packageVersion matches the pubspec version', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;

    expect(
      packageVersion,
      pubspec['version'],
      reason: 'run `dart run build_runner build`',
    );
  });
}
