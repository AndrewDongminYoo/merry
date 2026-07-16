import 'package:equatable/equatable.dart';
import 'package:merry/src/utils/shell_quote.dart' show shellSplit;

const String referencePrefix = '\$';
const String referenceNestingDelimiter = ':';

/// A helper class to represent a reference to a script.
class Reference extends Equatable {
  @override
  List<Object> get props => [script, extra];

  /// The script referenced to run.
  final String script;

  /// The extra arguments to pass down to the script.
  final List<String> extra;

  /// Constructs a constant [Reference] instance.
  const Reference({required this.script, required this.extra});

  /// Creates a [Reference] instance from a [String] input.
  /// The input string must start with a single character
  /// as specified via [referencePrefix].
  ///
  /// The tail is split the way a shell would, so the quoting an author wrote
  /// in the config survives: `$deploy --message "hello world"` forwards
  /// `hello world` as one argument.
  factory Reference.from(String input) {
    final paths = shellSplit(input.substring(1));

    final script = paths.isEmpty ? '' : paths.first;
    final extra = paths.skip(1).toList();

    return Reference(
      script: script.split(referenceNestingDelimiter).join(' '),
      extra: extra,
    );
  }
}
