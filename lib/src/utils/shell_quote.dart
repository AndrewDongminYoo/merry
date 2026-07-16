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
