import 'package:merry/commands.dart';
import 'package:test/test.dart';

void main() {
  test('deprecated RunCommmand alias remains constructible', () {
    expect(RunCommmand(), isA<RunCommand>());
  });
}
