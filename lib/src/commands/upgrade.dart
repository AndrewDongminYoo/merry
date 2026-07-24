import 'dart:io' show Platform, Process, ProcessStartMode, stdout;

import 'package:args/command_runner.dart';
import 'package:merry/utils.dart';
import 'package:merry/version.dart';
import 'package:tint/tint.dart';

/// The `merry upgrade` command
/// which will attempt to run the pub command to
/// upgrade the merry package itself.
///
/// It's an equivalent of executing `dart pub global activate merry` by
/// yourself.
class UpgradeCommand extends Command<int> {
  @override
  String get name => 'upgrade';

  @override
  String get description => 'upgrade to the latest version of merry itself';

  @override
  Future<int> run() {
    rejectRest(super.argResults!, usage);

    const info = Info(name: 'merry', version: packageVersion);

    stdout.writeln('> $info upgrade'.bold());
    return upgradeMerry(_startUpgradeProcess);
  }
}

/// Starts a trusted executable with an argument list for the self-upgrade.
typedef UpgradeProcess =
    Future<int> Function(
      String executable,
      List<String> arguments,
    );

/// Upgrades merry using the Dart executable that launched this process.
Future<int> upgradeMerry(UpgradeProcess startProcess) {
  return startProcess(
    Platform.resolvedExecutable,
    const ['pub', 'global', 'activate', 'merry'],
  );
}

Future<int> _startUpgradeProcess(
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
