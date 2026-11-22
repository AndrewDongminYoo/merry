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
/// [environment] (default [Platform.environment]) as fallback. Unknown
/// variables are left unchanged.
///
/// Both sources are spliced as text, so a value that carries a shell-active
/// character makes this throw a [FormatException] (see [assertShellInert]).
/// The environment is not trusted: a caller such as a CI job can set it.
String substituteVariables(
  String script,
  Map<String, String> variables, {
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  return script.replaceAllMapped(RegExp(r'\$\{(\w+)\}'), (match) {
    final name = match.group(1)!;
    final defined = variables[name];
    if (defined != null) {
      // (variables) values are spliced as text, so refuse to run when one
      // carries a shell-active character (e.g. `$(...)` or `;`).
      assertShellInert(defined, 'variable \${$name}');
      return defined;
    }
    final fallback = env[name];
    if (fallback == null) return match.group(0)!;
    assertShellInert(
      fallback,
      'environment variable \${$name}',
      // No hint on Windows: cmd expands %NAME% before it parses the command
      // line, so the value would run as command syntax there.
      hint: Platform.isWindows
          ? null
          : 'To pass this value, let the shell expand it: replace \${$name} with "\$$name", '
                'or with \$$name when the placeholder is already inside double quotes. '
                'When a letter, digit or _ follows the placeholder, end the name with a quote: '
                'write "\$$name"suffix, or "...\$$name""suffix..." inside double quotes. '
                'When the placeholder is inside single quotes, close them around it: '
                "'a\${$name}b' becomes 'a'\"\$$name\"'b'.",
    );
    return fallback;
  });
}
