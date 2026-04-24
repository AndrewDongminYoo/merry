import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:merry/commands.dart';
import 'package:merry/error.dart';
import 'package:merry/version.dart';

Future<void> main(List<String> arguments) async {
  final exitCode = await runMerry(arguments);
  exit(exitCode);
}

Future<int> runMerry(List<String> arguments) async {
  final runner = CommandRunner<int>('merry', 'A script runner/manager for dart.');

  runner
    ..addCommand(RunCommmand())
    ..addCommand(ListCommand())
    ..addCommand(UpgradeCommand())
    ..addCommand(SourceCommand())
    ..argParser.addFlag(
      'version',
      abbr: 'v',
      negatable: false,
      help: 'output the version number',
    );

  final argResults = runner.parse(arguments);

  if (argResults['version'] as bool) {
    stdout.writeln('merry version: $packageVersion');
    return 0;
  } else {
    try {
      return await runner.run(arguments) ?? 0;
      // ignore: avoid_catching_errors
    } on MerryError catch (error) {
      handleError(error);
      return 1;
    } catch (exception) {
      if (exception is UsageException && exception.message.startsWith('Could not find a command named')) {
        return await runMerry(['run', ...arguments]);
      } else {
        stderr.writeln(exception);
        return 1;
      }
    }
  }
}
