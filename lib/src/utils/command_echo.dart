import 'package:merry/src/utils/display_safe.dart' show displaySafe, displaySafeLines;
import 'package:merry/src/utils/shell_quote.dart' show shellQuote;

/// Builds the text that merry echoes before it runs a command.
///
/// [template] is the command as written in the config, after the `\$`
/// normalization and the `(workdir)` prefix but before `${NAME}` and `$N`
/// substitution, so a value taken from the environment or the command line is
/// not shown. [appended] are the extra arguments that no `$N` consumed; they
/// are the user's own command line, so they are shown in the [shellQuote] form
/// that runs, which keeps the boundary between two arguments visible.
///
/// Control characters are escaped with [displaySafe]. Line breaks in
/// [template] are kept, so a multi-line script prints as several lines. The
/// result carries no `$ ` prefix and no color.
String formatCommandEcho(String template, List<String> appended) {
  return [
    displaySafeLines(template.trim()),
    ...appended.map((arg) => displaySafe(shellQuote(arg))),
  ].join(' ');
}
