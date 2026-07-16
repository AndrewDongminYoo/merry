import 'dart:io' show Platform;

/// Characters that survive an unquoted round trip through the shell.
final _safePattern = RegExp(r'^[A-Za-z0-9_@%+=:,./-]+$');

/// Quotes [arg] so the shell passes it through as a single argument.
///
/// Arguments that need no quoting are returned as-is, so commands keep looking
/// the way the user wrote them when they are echoed back.
///
/// ponytail: the Windows branch is best-effort. `cmd` has no general quoting
/// rule — `"` around the value covers spaces, but metacharacters such as `%`
/// and `^` still expand. Use a proper argv-based spawn if that ever matters.
String shellQuote(String arg) {
  if (_safePattern.hasMatch(arg)) return arg;
  if (Platform.isWindows) return '"${arg.replaceAll('"', r'\"')}"';
  return "'${arg.replaceAll("'", r"'\''")}'";
}

/// Splits a shell command tail into the words the shell would pass as
/// arguments, so `--message "hello world"` becomes two words rather than
/// three.
///
/// [shellQuote] round-trips the result: quoting each word back into a command
/// reproduces the same argument list.
///
/// A backslash escapes the next character, except inside single quotes and
/// except on Windows, where `cmd` gives it no such meaning and it has to stay
/// a path separator.
///
/// ponytail: an unterminated quote takes the rest of the input as one word
/// rather than failing.
List<String> shellSplit(String input) {
  final words = <String>[];
  final current = StringBuffer();
  var hasWord = false;
  var escaped = false;
  String? openQuote;

  for (final char in input.split('')) {
    if (escaped) {
      current.write(char);
      escaped = false;
    } else if (!Platform.isWindows && char == r'\' && openQuote != "'") {
      escaped = true;
      hasWord = true;
    } else if (openQuote == null && (char == ' ' || char == '\t')) {
      if (hasWord) {
        words.add(current.toString());
        current.clear();
        hasWord = false;
      }
    } else if (openQuote == null && (char == "'" || char == '"')) {
      openQuote = char;
      hasWord = true;
    } else if (openQuote == char) {
      openQuote = null;
    } else {
      current.write(char);
      hasWord = true;
    }
  }

  if (hasWord) words.add(current.toString());
  return words;
}
