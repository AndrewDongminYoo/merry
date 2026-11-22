import 'dart:io' show stdout;

import 'package:args/command_runner.dart';
import 'package:merry/utils.dart';
import 'package:path/path.dart' as path;

/// Gets the absolute path of a file.
String _getAbsolutePath(String filePath) => path.normalize(path.absolute(filePath));

/// The text `merry source` prints for [sourcePath].
///
/// A terminal gets the path with control characters escaped, so a crafted
/// file name cannot rewrite the screen. A pipe or a command substitution gets
/// the path unchanged, because a script opens the file by that exact name.
String sourceOutput(String sourcePath, {required bool toTerminal}) => toTerminal ? displaySafe(sourcePath) : sourcePath;

/// The `merry source` command
/// which prints out the current config file location.
class SourceCommand extends Command<int> {
  SourceCommand() {
    super.argParser.addFlag(
      'absolute',
      abbr: 'a',
      help: 'determine whether to show absolute paths or not',
      negatable: false,
    );

    super.argParser.addFlag(
      'check',
      help: 'determine whether to check if the config file exists and is valid or not',
      defaultsTo: true,
    );
  }

  @override
  String get name => 'source';

  @override
  String get description => 'find the location of the merry config file';

  @override
  Future<int> run() async {
    final argResults = super.argResults!;
    rejectRest(argResults, usage);
    final check = argResults['check'] as bool;
    final absolute = argResults['absolute'] as bool;

    final pubspec = Pubspec();
    final source = await pubspec.getSource();

    if (check) await pubspec.getScripts();
    stdout.writeln(
      sourceOutput(absolute ? _getAbsolutePath(source) : source, toTerminal: stdout.hasTerminal),
    );
    return 0;
  }
}
