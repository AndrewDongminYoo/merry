import 'dart:io' show Platform;

import 'package:merry/bindings.dart' as bindings;
import 'package:merry/error.dart' show ErrorCode, MerryError;
import 'package:merry/src/utils/json_map.dart';
import 'package:merry/src/utils/positional_args.dart' show applyPositionalArgs;
import 'package:merry/utils.dart'
    show
        Definition,
        JsonMap,
        JsonMapExtension,
        Reference,
        aliasesDefinitionKey,
        collectVariables,
        currentPlatformKey,
        defaultDefinitionKey,
        referencePrefix,
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
        // check for a platform-specific script first
        final platformKey = currentPlatformKey;
        if (platformKey != null) {
          final platformScripts = scriptFound[platformKey];
          if (platformScripts != null && (platformScripts is List || platformScripts is String)) {
            _serializedDefinitions[scriptString] = Definition.from(
              platformScripts,
            );
            return _serializedDefinitions[scriptString]!;
          }
        }

        final scripts = scriptFound[scriptsDefinitionKey];
        final validity = scripts != null && (scripts is List || scripts is String);

        if (!validity) {
          // check for (default) key to support default scripts in nested groups
          final defaultScript = scriptFound[defaultDefinitionKey];
          if (defaultScript != null && (defaultScript is List || defaultScript is String)) {
            _serializedDefinitions[scriptString] = Definition.from(
              defaultScript,
            );
            return _serializedDefinitions[scriptString]!;
          }

          throw MerryError(
            type: ErrorCode.invalidScript,
            body: {'script': scriptString, 'paths': getPaths()},
          );
        }
      }

      _serializedDefinitions[scriptString] = Definition.from(scriptFound);
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

  String _escapeDoubleQuotes(String input) {
    if (Platform.isWindows) return input.replaceAll('"', '""');
    return input.replaceAll('\\', r'\\').replaceAll('"', r'\"');
  }

  /// Runs a script from the scripts map if it exists.
  Future<int> runScript(String script, {String extra = ''}) async {
    final canonical = _resolveAlias(script);

    final preScript = lookup('pre$canonical');
    if (preScript != null) await _runScript('pre$canonical');

    final exitCode = await _runScript(canonical, extra: extra);

    final postScript = lookup('post$canonical');
    if (postScript != null) await _runScript('post$canonical');

    return exitCode;
  }

  Future<int> _runScript(String scriptString, {String extra = ''}) async {
    final definition = getDefinition(scriptString);
    var exitCode = 0;

    for (final script in definition.scripts) {
      if (script.startsWith(referencePrefix)) {
        final ref = getReference(script);
        exitCode = await runScript(
          ref.script,
          extra: _joinStrings([ref.extra, extra]),
        );
      } else {
        // replace all \$ with $, they are not valid references
        var normalizedScript = script.replaceAll(
          '\\$referencePrefix',
          referencePrefix,
        );
        // prepend cd if a workdir is specified
        if (definition.workdir != null) {
          final escapedWorkdir = _escapeDoubleQuotes(definition.workdir!);
          final cdCmd = Platform.isWindows ? 'cd /d "$escapedWorkdir" &&' : 'cd "$escapedWorkdir" &&';
          normalizedScript = '$cdCmd $normalizedScript';
        }
        // apply ${VAR} substitution using (variables) definitions and env
        normalizedScript = substituteVariables(
          normalizedScript,
          getVariables(),
        );
        final positional = applyPositionalArgs(normalizedScript, extra);
        exitCode = await bindings.runScript(
          _joinStrings([positional.key, positional.value]),
        );
      }
    }

    return exitCode;
  }
}
