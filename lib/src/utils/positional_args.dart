import 'package:merry/src/utils/shell_quote.dart' show assertShellInert, shellQuote;

/// Replaces `$1`, `$2`, etc. in [script] with positional args from [args].
///
/// Returns a [MapEntry] where [MapEntry.key] is the substituted script and
/// [MapEntry.value] is the remaining unused args.
///
/// Substituted values are shell-quoted, so an arg containing spaces stays a
/// single argument. If [script] contains no `$N` tokens, [args] is returned
/// unchanged so it can be appended as before (backward-compatible).
///
/// ponytail: `$N` is spliced in as text, so the supported form is a bare
/// `$N` — a `$N` already written inside quotes (`echo "hi $1"`) carries the
/// added quotes through into the output. Making both forms work means letting
/// the shell expand its own positional parameters (`bash -c script -- args`),
/// which `cmd /C` cannot do.
MapEntry<String, List<String>> applyPositionalArgs(String script, List<String> args) {
  final positionalPattern = RegExp(r'\$(\d+)');
  if (!positionalPattern.hasMatch(script)) return MapEntry(script, args);

  final usedIndices = <int>{};

  final substituted = script.replaceAllMapped(positionalPattern, (match) {
    final index = int.parse(match.group(1)!) - 1; // $1 → args[0]
    if (index >= 0 && index < args.length) {
      usedIndices.add(index);
      // A referenced arg may be substituted inside quotes, so refuse to run
      // when it carries a shell-active character rather than risk injection.
      assertShellInert(args[index], 'positional argument \$${index + 1}');
      return shellQuote(args[index]);
    }
    return ''; // out-of-range token → empty string
  });

  final remaining = [
    for (var i = 0; i < args.length; i++)
      if (!usedIndices.contains(i)) args[i],
  ];

  return MapEntry(substituted, remaining);
}
