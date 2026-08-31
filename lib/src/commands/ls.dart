import 'dart:convert' show JsonEncoder;
import 'dart:io' show stdout;

import 'package:args/command_runner.dart';
import 'package:merry/utils.dart';
import 'package:tint/tint.dart';

/// Returns length of the longest string in a list, or `0` when empty.
int _getLongestStringLength(List<String> strings) {
  return strings.fold(0, (longest, str) => str.length > longest ? str.length : longest);
}

/// Returns the path prefix to display in a tree.
String _getPrefix(int current, int len) {
  return current == len - 1 ? '└──' : '├──';
}

/// The `merry ls` command
/// which will print a recursive tree representation of
/// all the available scripts within the current config.
///
/// Notes:
///
/// - the name & version of the package by the config will also be printed out
/// - references will starts with an `$` and will have a different color
class ListCommand extends Command<int> {
  ListCommand() {
    super.argParser
      ..addFlag(
        'description',
        abbr: 'd',
        help: 'whether to show descriptions or not',
        negatable: false,
      )
      ..addOption(
        'output',
        abbr: 'o',
        defaultsTo: 'tree',
        allowed: ['tree', 'json', 'tasks'],
        allowedHelp: {
          'tree': 'human-readable tree (default)',
          'json': 'machine-readable JSON for tooling integration',
          'tasks': 'VS Code tasks.json configuration',
        },
        help: 'output format',
      );
  }

  @override
  String get name => 'ls';

  @override
  String get description => 'list available scripts in the current config';

  @override
  Future<int> run() async {
    final argResults = super.argResults!;
    rejectRest(argResults, usage);
    final showDescriptions = argResults['description'] as bool;
    final outputFormat = argResults['output'] as String;

    final pubspec = Pubspec();
    final info = await pubspec.getInfo();
    final scripts = await pubspec.getScripts();

    final registry = ScriptsRegistry(scripts);
    final paths = registry.getPaths()..sort();
    final definitions = paths.map((path) => registry.getDefinition(path)).toList();

    if (outputFormat == 'json') {
      _printJson(info, paths, definitions);
      return 0;
    }

    if (outputFormat == 'tasks') {
      _printTasks(paths, definitions);
      return 0;
    }

    _printTree(info, paths, definitions, showDescriptions);
    return 0;
  }

  void _printJson(Info info, List<String> paths, List<Definition> definitions) {
    final nameSet = paths.toSet();
    final scripts = <Map<String, dynamic>>[];

    for (var i = 0; i < paths.length; i++) {
      final name = paths[i];
      final def = definitions[i];

      final entry = <String, dynamic>{'name': name, 'commands': def.scripts};
      if (def.description != null) entry['description'] = def.description;
      if (def.workdir != null) entry['workdir'] = def.workdir;
      // Surface a non-default execution mode so tooling can tell whether later
      // commands keep running after a failure.
      if (def.execution != 'multiple') entry['execution'] = def.execution;

      // hooks that run automatically before/after this script
      final hooks = <String, String>{};
      if (nameSet.contains('pre$name')) hooks['pre'] = 'pre$name';
      if (nameSet.contains('post$name')) hooks['post'] = 'post$name';
      if (hooks.isNotEmpty) entry['hooks'] = hooks;

      // if this script is itself a pre/post hook for another script
      final hookTarget = _hookTargetOf(name, nameSet);
      if (hookTarget != null) entry['hook_for'] = hookTarget;

      scripts.add(entry);
    }

    const encoder = JsonEncoder.withIndent('  ');
    stdout.writeln(encoder.convert({'name': info.name, 'version': info.version, 'scripts': scripts}));
  }

  /// Returns the script that [name] is an automatic `pre`/`post` hook for,
  /// or `null` when [name] is a script in its own right.
  String? _hookTargetOf(String name, Set<String> names) {
    for (final prefix in const ['pre', 'post']) {
      if (!name.startsWith(prefix) || name.length <= prefix.length) continue;
      final target = name.substring(prefix.length);
      if (names.contains(target)) return target;
    }
    return null;
  }

  void _printTasks(List<String> paths, List<Definition> definitions) {
    final nameSet = paths.toSet();
    final tasks = <Map<String, dynamic>>[];

    for (var i = 0; i < paths.length; i++) {
      final name = paths[i];
      // hooks run together with the script they belong to, so they would only
      // be misleading as separate entries in the task list
      if (_hookTargetOf(name, nameSet) != null) continue;

      // `merry <name>` only reaches a script when the name is not one of
      // merry's own subcommands, so a script called `ls` or `upgrade` would
      // run the subcommand instead; the explicit `run` avoids that entirely.
      // A process task also passes the name as one argument, which keeps the
      // space in a nested name such as `build debug` out of shell quoting.
      final task = <String, dynamic>{
        'label': 'merry: $name',
        'type': 'process',
        'command': 'dart',
        'args': ['run', 'merry:merry', 'run', name],
        // without an explicit matcher VS Code asks how to scan the output on
        // every single run
        'problemMatcher': <String>[],
      };

      final description = definitions[i].description;
      if (description != null) task['detail'] = description;

      tasks.add(task);
    }

    const encoder = JsonEncoder.withIndent('  ');
    stdout.writeln(encoder.convert({'version': '2.0.0', 'tasks': tasks}));
  }

  void _printTree(
    Info info,
    List<String> paths,
    List<Definition> definitions,
    bool showDescriptions,
  ) {
    final references = definitions
        .map((def) => def.scripts.where((s) => s.startsWith(referencePrefix)).toList())
        .toList();

    final buffer = StringBuffer();
    buffer.writeln('+ $info');
    buffer.writeln('│');

    final longestScriptLength = _getLongestStringLength(paths);

    for (final pathEntry in paths.asMap().entries) {
      final pathIndex = pathEntry.key;
      final path = pathEntry.value;
      final description = definitions[pathIndex].description;
      final refs = references[pathIndex];

      final formattedDescription = showDescriptions && description != null
          ? '${''.padLeft(longestScriptLength + 4 - path.length)} - $description'.gray()
          : '';

      buffer.writeln('${_getPrefix(pathIndex, paths.length)} $path $formattedDescription');

      for (final refEntry in refs.asMap().entries) {
        final referenceIndex = refEntry.key;
        final reference = refEntry.value;

        final formattedReference = reference
            .replaceAll('\\$referencePrefix', referencePrefix)
            .split(referenceNestingDelimiter)
            .join(' ')
            .green();

        buffer.writeln(
          '${pathIndex == paths.length - 1 ? ' ' : '│'}'
          '   '
          '${_getPrefix(referenceIndex, refs.length)} $formattedReference',
        );
      }
    }

    stdout.writeln(buffer.toString());
  }
}
