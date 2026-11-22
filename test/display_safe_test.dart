import 'package:merry/utils.dart';
import 'package:test/test.dart';

void main() {
  group('displaySafe', () {
    test('keeps ordinary text, Unicode letters and tree glyphs as-is', () {
      expect(displaySafe('build debug'), 'build debug');
      expect(displaySafe('한글 설명'), '한글 설명');
      expect(displaySafe(r'$build d --debug'), r'$build d --debug');
      expect(displaySafe('café ✓'), 'café ✓');
    });

    test('escapes C0 controls, DEL and C1 controls', () {
      expect(displaySafe('a\x1B[2Jb'), r'a\x1B[2Jb');
      expect(displaySafe('a\nb\rc\td'), r'a\x0Ab\x0Dc\x09d');
      expect(displaySafe('\x00\x07\x7F'), r'\x00\x07\x7F');
      expect(displaySafe('a\x9Bb'), r'a\x9Bb');
    });

    test('escapes bidirectional overrides and isolates', () {
      final override = String.fromCharCode(0x202E);
      final isolate = String.fromCharCode(0x2066);
      expect(displaySafe('abc${override}def'), r'abc\u{202E}def');
      expect(displaySafe('${isolate}x'), r'\u{2066}x');
    });
  });
}
