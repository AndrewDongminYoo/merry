/// Replaces `$1`, `$2`, etc. in [script] with positional args from [extra].
///
/// Returns a [MapEntry] where [MapEntry.key] is the substituted script and
/// [MapEntry.value] is the remaining unused extra args.
///
/// If [script] contains no `$N` tokens, [extra] is returned unchanged so it
/// can be appended as before (backward-compatible).
MapEntry<String, String> applyPositionalArgs(String script, String extra) {
  final positionalPattern = RegExp(r'\$(\d+)');
  if (!positionalPattern.hasMatch(script)) return MapEntry(script, extra);

  final args = extra.trim().isEmpty ? <String>[] : extra.trim().split(RegExp(r'\s+'));
  final usedIndices = <int>{};

  final substituted = script.replaceAllMapped(positionalPattern, (match) {
    final index = int.parse(match.group(1)!) - 1; // $1 → args[0]
    if (index >= 0 && index < args.length) {
      usedIndices.add(index);
      return args[index];
    }
    return ''; // out-of-range token → empty string
  });

  final remaining = [
    for (var i = 0; i < args.length; i++)
      if (!usedIndices.contains(i)) args[i],
  ].join(' ');

  return MapEntry(substituted, remaining);
}
