import 'package:merry/commands.dart';
import 'package:test/test.dart';

void main() {
  test('upgrade command reserves the legacy update command name', () {
    expect(UpgradeCommand().aliases, contains('update'));
  });
}
