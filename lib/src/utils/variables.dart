import 'dart:io' show Platform;

import 'package:merry/src/utils/shell_quote.dart' show assertShellInert;
import 'package:merry/utils.dart' show JsonMap, variablesDefinitionKey;

/// Collects all variable definitions from [map] by scanning for `(variables)`
/// sections at every nesting level. Later definitions override earlier ones.
Map<String, String> collectVariables(JsonMap map) {
  final result = <String, String>{};
  final metaPattern = RegExp(r'^\(\w+\)$');

  for (final key in map.keys) {
    if (key == variablesDefinitionKey) {
      final vars = map[key];
      if (vars is Map) {
        vars.forEach((k, v) {
          if (v != null) result[k.toString()] = v.toString();
        });
      }
      continue;
    }

    if (metaPattern.hasMatch(key)) continue;

    final value = map[key];
    if (value is Map) {
      final nested = value.map((k, v) => MapEntry(k.toString(), v)).cast<String, dynamic>();
      result.addAll(collectVariables(nested));
    }
  }

  return result;
}

/// Replaces `${VAR}` tokens in [script] using [variables] first, then
/// [Platform.environment] as fallback. Unknown variables are left unchanged.
String substituteVariables(String script, Map<String, String> variables) {
  return script.replaceAllMapped(RegExp(r'\$\{(\w+)\}'), (match) {
    final name = match.group(1)!;
    final defined = variables[name];
    if (defined != null) {
      // (variables) values are spliced as text, so refuse to run when one
      // carries a shell-active character (e.g. `$(...)` or `;`).
      assertShellInert(defined, 'variable \${$name}');
      return defined;
    }
    return Platform.environment[name] ?? match.group(0)!;
  });
}
