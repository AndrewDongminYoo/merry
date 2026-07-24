import 'dart:io' show Platform, Process, ProcessStartMode, stdout;

import 'package:args/command_runner.dart';
import 'package:merry/utils.dart';
import 'package:merry/version.dart';
import 'package:tint/tint.dart';

typedef ProcessRunner =
    Future<int> Function(
      String executable,
      List<String> arguments,
    );

Future<int> _runProcess(
  String executable,
  List<String> arguments,
) async {
  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}

/// The `merry upgrade` command
/// which will attempt to run the pub command to
/// upgrade the merry package itself.
///
/// It's an equivalent of executing the
/// `dart pub global activate merry` by yourself.
class UpgradeCommand extends Command<int> {
  UpgradeCommand({ProcessRunner processRunner = _runProcess}) : _processRunner = processRunner;

  final ProcessRunner _processRunner;

  @override
  String get name => 'upgrade';

  @override
  String get description => 'upgrade to the latest version of merry itself';

  @override
  Future<int> run() {
    rejectRest(super.argResults!, usage);

    const info = Info(name: 'merry', version: packageVersion);

    stdout.writeln('> $info upgrade'.bold());
    return _processRunner(
      Platform.resolvedExecutable,
      const ['pub', 'global', 'activate', 'merry'],
    );
  }
}
