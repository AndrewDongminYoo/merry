import 'dart:io' show Platform;

import 'package:merry/commands.dart';
import 'package:test/test.dart';

void main() {
  test('upgrade invokes the current Dart executable without a shell', () async {
    String? executable;
    List<String>? arguments;

    final exitCode = await upgradeMerry((command, commandArguments) async {
      executable = command;
      arguments = commandArguments;
      return 17;
    });

    expect(executable, Platform.resolvedExecutable);
    expect(arguments, ['pub', 'global', 'activate', 'merry']);
    expect(exitCode, 17);
  });
}
