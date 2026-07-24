import 'package:merry/utils.dart';
import 'package:test/test.dart';

void main() {
  test(
    'SIGINT in a pre-hook stops the main script and post-hook',
    () async {
      final commands = <String>[];
      final registry = ScriptsRegistry(
        {
          'predeploy': 'pre-command',
          'deploy': 'main-command',
          'postdeploy': 'post-command',
        },
        runCommand: (command) async {
          commands.add(command);
          return 130;
        },
      );

      expect(await registry.runScript('deploy'), 130);
      expect(commands, ['pre-command']);
    },
  );

  test('SIGINT stops the remaining commands in a script list', () async {
    final commands = <String>[];
    final registry = ScriptsRegistry(
      {
        'deploy': ['first-command', 'later-command'],
      },
      runCommand: (command) async {
        commands.add(command);
        return 130;
      },
    );

    expect(await registry.runScript('deploy'), 130);
    expect(commands, ['first-command']);
  });
}
