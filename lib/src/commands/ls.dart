import 'dart:convert' show JsonEncoder;
import 'dart:io' show stdout;

import 'package:args/command_runner.dart';
import 'package:merry/utils.dart';
import 'package:tint/tint.dart';

/// A displayed command group or runnable script in the command tree.
class _TreeNode {
  _TreeNode({required this.fullPath});

  final String fullPath;
  final Map<String, _TreeNode> children = {};
  Definition? definition;
  bool isDefault = false;
  String? hiddenDefaultReference;
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

    _printTree(info, paths, definitions, registry, showDescriptions);
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
    ScriptsRegistry registry,
    bool showDescriptions,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('+ $info');
    buffer.writeln('│');

    final roots = <String, _TreeNode>{};
    for (final entry in paths.asMap().entries) {
      final segments = entry.value.split(' ');
      var nodes = roots;
      _TreeNode? node;
      final fullPathSegments = <String>[];
      for (final segment in segments) {
        fullPathSegments.add(segment);
        node = nodes.putIfAbsent(segment, () => _TreeNode(fullPath: fullPathSegments.join(' ')));
        nodes = node.children;
      }
      node!.definition = definitions[entry.key];
    }

    void markDefaults(Iterable<_TreeNode> nodes) {
      for (final node in nodes) {
        final source = registry.lookup(node.fullPath);
        if (source is Map) {
          final defaultValue = source[defaultDefinitionKey];
          if (defaultValue is String &&
              defaultValue.startsWith(referencePrefix) &&
              runnableScripts(source) == defaultValue) {
            final reference = registry.getReference(defaultValue);
            final target = registry.getAliasMap()[reference.script] ?? reference.script;
            final targetNode = _findNode(roots, target);
            if (targetNode != null) {
              targetNode.isDefault = true;
              if (reference.extra.isEmpty) node.hiddenDefaultReference = defaultValue;
            }
          }
        }
        markDefaults(node.children.values);
      }
    }

    markDefaults(roots.values);
    _writeTree(buffer, roots.values, '', showDescriptions);

    stdout.writeln(buffer.toString());
  }

  _TreeNode? _findNode(Map<String, _TreeNode> roots, String path) {
    _TreeNode? node;
    var nodes = roots;
    for (final segment in path.split(' ')) {
      node = nodes[segment];
      if (node == null) return null;
      nodes = node.children;
    }
    return node;
  }

  void _writeTree(StringBuffer buffer, Iterable<_TreeNode> nodes, String prefix, bool showDescriptions) {
    final orderedNodes = nodes.toList()..sort((a, b) => a.fullPath.compareTo(b.fullPath));
    for (final entry in orderedNodes.asMap().entries) {
      final node = entry.value;
      final isLast = entry.key == orderedNodes.length - 1;
      final description = node.definition?.description;
      final formattedDescription = showDescriptions && description != null ? ' - $description'.gray() : '';
      buffer.writeln(
        '$prefix${isLast ? '└──' : '├──'} ${node.fullPath}${node.isDefault ? ' (*default)' : ''}$formattedDescription',
      );

      final contentPrefix = '$prefix${isLast ? '    ' : '│   '}';
      final references =
          node.definition?.scripts.where(
            (script) => script.startsWith(referencePrefix) && script != node.hiddenDefaultReference,
          ) ??
          const <String>[];
      for (final reference in references) {
        final formattedReference = reference
            .replaceAll('\\$referencePrefix', referencePrefix)
            .split(referenceNestingDelimiter)
            .join(' ')
            .green();
        buffer.writeln('$contentPrefix╰⇾ $formattedReference');
      }
      _writeTree(buffer, node.children.values, contentPrefix, showDescriptions);
    }
  }
}
