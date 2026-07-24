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

/// Any character a substituted value must not contain to stay inert.
///
/// merry splices positional arguments and variable values into the command
/// text. Single-quoting keeps them inert in a *bare* position, but if the
/// author placed the placeholder inside quotes the value can escape that
/// context — `"$1"` evaluates a `$(...)` payload, and `'$1'` lets a `;` start a
/// new command. Knowing the surrounding context needs a shell parser (which is
/// unsound to approximate), so instead we refuse to run when the value carries
/// any character the shell could act on. The allowed set matches [_safePattern]
/// plus a space, which is inert in every quoting context.
final _shellUnsafePattern = RegExp('[^A-Za-z0-9_@%+=:,./ -]');

/// Throws a [FormatException] if [value] carries a shell-active character.
///
/// [describe] names the source for the error, e.g. `positional argument $1`.
void assertShellInert(String value, String describe) {
  if (_shellUnsafePattern.hasMatch(value)) {
    throw FormatException(
      'Refusing to run: $describe contains a character the shell could '
      'interpret. merry substitutes it as text and cannot keep it inert inside '
      'quotes. Allowed: letters, digits, spaces and _@%+=:,./- .',
    );
  }
}

/// Builds a shell command that changes to [workdir] before continuing.
///
/// On POSIX, [shellQuote] prevents the shell from evaluating command
/// substitutions or other metacharacters in the directory name.
String shellChangeDirectory(String workdir) {
  if (Platform.isWindows) {
    final escaped = workdir.replaceAll('"', '""');
    return 'cd /d "$escaped" &&';
  }
  return 'cd ${shellQuote(workdir)} &&';
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
