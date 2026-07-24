import 'package:merry/error.dart';
import 'package:merry/utils.dart';
import 'package:test/test.dart';

/// Matches a [MerryError] reporting a reference loop along [cycle].
Matcher isCircularReference(List<String> cycle) => isA<MerryError>()
    .having((error) => error.type, 'type', ErrorCode.circularReference)
    .having((error) => error.body['cycle'], 'cycle', cycle);

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

  test('runScript rejects a self-referencing script', () async {
    final registry = ScriptsRegistry({'loop': r'$loop'});

    await expectLater(
      registry.runScript('loop'),
      throwsA(isCircularReference(['loop', 'loop'])),
    );
  });

  test('runScript rejects a cycle spanning several scripts', () async {
    final registry = ScriptsRegistry({'a': r'$b', 'b': r'$a'});

    await expectLater(
      registry.runScript('a'),
      throwsA(isCircularReference(['a', 'b', 'a'])),
    );
  });

  test('runScript rejects a cycle reached through a pre-hook', () async {
    // The hook itself is not on the reference path, so the loop is only caught
    // because the script that owns the hook is.
    final registry = ScriptsRegistry({'deploy': 'main-command', 'predeploy': r'$deploy'});

    await expectLater(
      registry.runScript('deploy'),
      throwsA(isCircularReference(['deploy', 'deploy'])),
    );
  });

  test('runScript allows the same script to be referenced more than once', () async {
    // Cycle detection tracks the active call path, not every script already
    // seen: repeating a reference in sequence is legal and must still run.
    final commands = <String>[];
    final registry = ScriptsRegistry(
      {
        'ci': [r'$check', r'$check'],
        'check': 'check-command',
      },
      runCommand: (command) async {
        commands.add(command);
        return 0;
      },
    );

    expect(await registry.runScript('ci'), 0);
    expect(commands, ['check-command', 'check-command']);
  });
}
