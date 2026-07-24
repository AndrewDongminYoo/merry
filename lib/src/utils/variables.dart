import 'dart:io' show Platform;

import 'package:merry/src/utils/shell_quote.dart' show shellQuote;
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

/// Makes [variables] available to `${VAR}` tokens in [script].
///
/// On POSIX, values are assigned as quoted shell data instead of interpolated
/// into the command source. Environment-only and unknown variables stay in the
/// script for the shell to expand normally.
String substituteVariables(String script, Map<String, String> variables) {
  if (Platform.isWindows) {
    return script.replaceAllMapped(RegExp(r'\$\{(\w+)\}'), (match) {
      final name = match.group(1)!;
      final value = variables[name] ?? Platform.environment[name];
      return value == null ? match.group(0)! : _escapeWindowsShellValue(value);
    });
  }

  final referencedNames = RegExp(
    r'\$\{(\w+)\}',
  ).allMatches(script).map((match) => match.group(1)!).toSet();
  final assignments = referencedNames
      .where(variables.containsKey)
      .map((name) => '$name=${shellQuote(variables[name]!)}; export $name;')
      .join(' ');

  return assignments.isEmpty ? script : '$assignments $script';
}

String _escapeWindowsShellValue(String value) {
  return value.replaceAllMapped(
    RegExp('[&|<>()^%!" ]'),
    (match) => '^${match.group(0)}',
  );
}
