import 'dart:io' show stdout;

import 'package:args/command_runner.dart';
import 'package:merry/utils.dart';
import 'package:merry/version.dart';
import 'package:tint/tint.dart';

/// The `merry upgrade` command
/// which will attempt to run the pub command to
/// upgrade the merry package itself.
///
/// It's an equivalent of executing the
/// `dart run pub global activate merry` by yourself.
class UpgradeCommand extends Command<int> {
  @override
  String get name => 'upgrade';

  @override
  String get description => 'upgrade to the latest version of merry itself';

  @override
  Future<int> run() {
    const info = Info(name: 'merry', version: packageVersion);
    final registry = ScriptsRegistry({
      'upgrade': 'dart run pub global activate merry',
    });

    stdout.writeln('> $info upgrade'.bold());
    return registry.runScript('upgrade');
  }
}
