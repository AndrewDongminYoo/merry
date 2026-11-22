/// Whether a terminal or log viewer acts on [codePoint] instead of showing it:
/// C0 controls, DEL, C1 controls, and the Unicode bidirectional embeddings,
/// overrides and isolates that can reorder the text around them.
bool _isUnsafeForDisplay(int codePoint) =>
    codePoint <= 0x1F ||
    (codePoint >= 0x7F && codePoint <= 0x9F) ||
    (codePoint >= 0x202A && codePoint <= 0x202E) ||
    (codePoint >= 0x2066 && codePoint <= 0x2069);

/// Makes a config-supplied [text] safe to print in human-readable output.
///
/// Every control character becomes a visible escape such as `\x1B` or
/// `\u{202E}`, so an untrusted config cannot move the cursor, recolor, clear
/// or rewrite the terminal. All other text, including non-ASCII letters, is
/// returned as-is.
String displaySafe(String text) {
  if (!text.runes.any(_isUnsafeForDisplay)) return text;

  final buffer = StringBuffer();
  for (final codePoint in text.runes) {
    if (!_isUnsafeForDisplay(codePoint)) {
      buffer.writeCharCode(codePoint);
      continue;
    }
    final hex = codePoint.toRadixString(16).toUpperCase();
    buffer.write(codePoint <= 0xFF ? '\\x${hex.padLeft(2, '0')}' : '\\u{$hex}');
  }
  return buffer.toString();
}

/// Like [displaySafe], but keeps line breaks.
///
/// [text] is split on `\n` and `\r\n`, each line is escaped on its own, and
/// the lines are joined with `\n`, so multi-line text still prints as several
/// lines. A lone `\r` is not a line break and is escaped.
String displaySafeLines(String text) => text.split(_lineBreak).map(displaySafe).join('\n');

final _lineBreak = RegExp('\r?\n');
