import 'dart:io' show Platform;

import 'package:args/command_runner.dart';
import 'package:merry/commands.dart';
import 'package:test/test.dart';

void main() {
  test('upgrade invokes pub through the current Dart SDK executable', () async {
    String? executable;
    List<String>? arguments;
    final runner = CommandRunner<int>('merry', 'test')
      ..addCommand(
        UpgradeCommand(
          processRunner: (command, args) async {
            executable = command;
            arguments = args;
            return 0;
          },
        ),
      );

    final exitCode = await runner.run(['upgrade']);

    expect(exitCode, 0);
    expect(executable, Platform.resolvedExecutable);
    expect(arguments, ['pub', 'global', 'activate', 'merry']);
  });
}
