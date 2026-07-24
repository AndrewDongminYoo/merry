import 'dart:io' show Platform;

import 'package:merry/bindings.dart' as bindings;
import 'package:merry/error.dart' show ErrorCode, MerryError;
import 'package:merry/src/utils/json_map.dart';
import 'package:merry/src/utils/positional_args.dart' show applyPositionalArgs, splitPositionalArgs;
import 'package:merry/src/utils/shell_quote.dart' show shellChangeDirectory, shellQuote;
import 'package:merry/utils.dart'
    show
        Definition,
        JsonMap,
        JsonMapExtension,
        Reference,
        aliasesDefinitionKey,
        collectVariables,
        referencePrefix,
        runnableScripts,
        scriptsDefinitionKey,
        substituteVariables;

final _metaKeyPattern = RegExp(r'^\(\w+\)$');

/// Join a list of [String] with Space as delimiter.
String _joinStrings(List<String> list) => list.map((s) => s.trim()).join(' ');

/// A class that holds scripts and provides utilities
/// to work with them.
class ScriptsRegistry {
  /// A map of scripts retrieved from `pubspec.yaml`.
  final JsonMap scripts;

  /// Constructs a [ScriptsRegistry] from a [JsonMap].
  ScriptsRegistry(JsonMap scriptsMap) : scripts = scriptsMap;

  /// A list of all possible paths,
  /// used as a mean of memoization.
  List<String>? _paths;

  /// Returns all valid paths to access values from the scripts map.
  List<String> getPaths() {
    return _paths ??= scripts.getPaths();
  }

  /// Previous search results,
  /// used as a mean of memoization.
  final Map<String, dynamic> _searchResults = {};

  /// Searches for a given path in the scripts map.
  dynamic lookup(String path) {
    return _searchResults[path] ??= scripts.lookup(path);
  }

  /// Previously serialized definitions,
  /// used as a mean of memoization.
  final Map<String, Definition> _serializedDefinitions = {};

  /// Get a serialized [Definition] for a script string if it exists.
  /// This function will throw errors if the script is not defined
  /// or if the script is not valid.
  Definition getDefinition(String scriptString) {
    if (!_serializedDefinitions.containsKey(scriptString)) {
      final scriptFound = lookup(scriptString);

      /// for when script is not defined at all
      if (scriptFound == null) {
        throw MerryError(
          type: ErrorCode.scriptNotDefined,
          body: {'script': scriptString, 'suggestions': getPaths()},
        );
      }

      // for when script is not a type we want
      if (scriptFound is! Map && scriptFound is! List && scriptFound is! String) {
        throw MerryError(
          type: ErrorCode.invalidScript,
          body: {'script': scriptString},
        );
      }

      // for when script is a map
      if (scriptFound is Map) {
        final scripts = runnableScripts(scriptFound);

        if (scripts == null) {
          throw MerryError(
            type: ErrorCode.invalidScript,
            body: {'script': scriptString, 'paths': getPaths()},
          );
        }

        // keep the surrounding (description)/(workdir) when the commands come
        // from a platform or (default) key instead of (scripts)
        _serializedDefinitions[scriptString] = Definition.from({
          ...scriptFound,
          scriptsDefinitionKey: scripts,
        });
      } else {
        _serializedDefinitions[scriptString] = Definition.from(scriptFound);
      }
    }

    return _serializedDefinitions[scriptString]!;
  }

  /// Previously constructed references,
  /// used as a mean of memoization.
  final Map<String, Reference> _references = {};

  /// Lazily-collected variable map from all `(variables)` sections.
  Map<String, String>? _variables;

  /// Returns the collected variable map, building it lazily on first call.
  Map<String, String> getVariables() {
    return _variables ??= collectVariables(scripts);
  }

  /// Compute [Reference] parts from a script string.
  Reference getReference(String scriptString) {
    return _references[scriptString] ??= Reference.from(scriptString);
  }

  /// Lazily-built map of alias → canonical script path.
  Map<String, String>? _aliasMap;

  /// Builds a flat alias → canonical path map by recursively scanning [map].
  Map<String, String> _collectAliases(JsonMap map, String prefix) {
    final result = <String, String>{};

    for (final key in map.keys) {
      if (_metaKeyPattern.hasMatch(key)) continue;

      final fullPath = prefix.isEmpty ? key : '$prefix $key';
      final value = map[key];

      if (value is Map) {
        final jsonValue = value.asJsonMap();
        final raw = jsonValue[aliasesDefinitionKey];
        if (raw != null) {
          final aliasList = raw is List ? raw.map((e) => e.toString()).toList() : [raw.toString()];
          for (final alias in aliasList) {
            final aliasPath = prefix.isEmpty ? alias : '$prefix $alias';
            result[aliasPath] = fullPath;
          }
        }
        result.addAll(_collectAliases(jsonValue, fullPath));
      }
    }
    return result;
  }

  /// Returns the alias map, building it lazily on first call.
  Map<String, String> getAliasMap() {
    return _aliasMap ??= _collectAliases(scripts, '');
  }

  /// Returns the canonical script path for [script], resolving aliases.
  String _resolveAlias(String script) {
    return getAliasMap()[script] ?? script;
  }

  /// Runs a script from the scripts map if it exists.
  Future<int> runScript(String script, {List<String> extra = const []}) async {
    final canonical = _resolveAlias(script);

    final preScript = lookup('pre$canonical');
    if (preScript != null) await _runScript('pre$canonical');

    final exitCode = await _runScript(canonical, extra: extra);

    final postScript = lookup('post$canonical');
    if (postScript != null) await _runScript('post$canonical');

    return exitCode;
  }

  Future<int> _runScript(String scriptString, {List<String> extra = const []}) async {
    final definition = getDefinition(scriptString);
    var exitCode = 0;

    for (final script in definition.scripts) {
      if (script.startsWith(referencePrefix)) {
        final ref = getReference(script);
        exitCode = await runScript(
          ref.script,
          extra: [...ref.extra, ...extra],
        );
      } else {
        // replace all \$ with $, they are not valid references
        var normalizedScript = script.replaceAll(
          '\\$referencePrefix',
          referencePrefix,
        );
        // prepend cd if a workdir is specified
        if (definition.workdir != null) {
          final cdCmd = shellChangeDirectory(definition.workdir!);
          normalizedScript = '$cdCmd $normalizedScript';
        }

        if (Platform.isWindows) {
          // `cmd /C` cannot take positional parameters, so keep the best-effort
          // inline substitution: variables and $N are quoted and spliced into
          // the command text (see the caveats on shellQuote/applyPositionalArgs).
          normalizedScript = substituteVariables(normalizedScript, getVariables());
          final positional = applyPositionalArgs(normalizedScript, extra);
          exitCode = await bindings.runScript(
            _joinStrings([positional.key, ...positional.value.map(shellQuote)]),
          );
        } else {
          // POSIX: leave $N and ${VAR} literal and let bash expand them from
          // out-of-band positional parameters and the environment, so untrusted
          // values are never interpolated into shell source. Unreferenced args
          // are appended (shell-quoted, in unquoted trailing position — safe).
          final split = splitPositionalArgs(normalizedScript, extra);
          final command = split.append.isEmpty
              ? normalizedScript
              : _joinStrings([normalizedScript, ...split.append.map(shellQuote)]);
          exitCode = await bindings.runScript(
            command,
            args: split.positional,
            env: getVariables(),
          );
        }
      }
    }

    return exitCode;
  }
}
