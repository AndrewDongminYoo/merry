import 'dart:io' show Platform;

import 'package:merry/src/utils/shell_quote.dart' show shellQuote;

/// Replaces `$1`, `$2`, etc. in [script] with positional args from [args].
///
/// Returns a [MapEntry] where [MapEntry.key] is the substituted script and
/// [MapEntry.value] is the remaining unused args.
///
/// Substituted values are escaped for their surrounding shell quote context,
/// so they remain data even when they contain command substitutions or other
/// metacharacters. If [script] contains no `$N` tokens, [args] is returned
/// unchanged so it can be appended as before (backward-compatible).
MapEntry<String, List<String>> applyPositionalArgs(String script, List<String> args) {
  final positionalPattern = RegExp(r'\$(\d+)');
  if (!positionalPattern.hasMatch(script)) return MapEntry(script, args);

  final usedIndices = <int>{};
  String? openQuote;
  var escaped = false;
  var scannedThrough = 0;

  final substituted = script.replaceAllMapped(positionalPattern, (match) {
    for (final char in script.substring(scannedThrough, match.start).split('')) {
      if (escaped) {
        escaped = false;
      } else if (!Platform.isWindows && char == r'\' && openQuote != "'") {
        escaped = true;
      } else if (openQuote == null && (char == "'" || char == '"')) {
        openQuote = char;
      } else if (openQuote == char) {
        openQuote = null;
      }
    }
    scannedThrough = match.end;

    final index = int.parse(match.group(1)!) - 1; // $1 → args[0]
    if (index >= 0 && index < args.length) {
      usedIndices.add(index);
      final arg = args[index];
      if (!Platform.isWindows && openQuote == '"') {
        return arg.replaceAll(r'\', r'\\').replaceAll(r'$', r'\$').replaceAll('`', r'\`').replaceAll('"', r'\"');
      }
      if (!Platform.isWindows && openQuote == "'") {
        return arg.replaceAll("'", r"'\''");
      }
      return shellQuote(arg);
    }
    return ''; // out-of-range token → empty string
  });

  final remaining = [
    for (var i = 0; i < args.length; i++)
      if (!usedIndices.contains(i)) args[i],
  ];

  return MapEntry(substituted, remaining);
}
