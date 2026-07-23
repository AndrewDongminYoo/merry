import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('publish workflow accepts only semantic version tags', () {
    final workflow = File('.github/workflows/publish.yml').readAsStringSync();

    expect(workflow, contains(r'[[ "$GITHUB_REF_NAME" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]'));
  });
}
