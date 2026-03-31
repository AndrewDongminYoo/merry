import 'package:equatable/equatable.dart' show EquatableMixin;
import 'package:merry/src/error/error_code.dart' show ErrorCode;

/// A custom error type used to catch custom errors
/// with the type [ErrorCode].
class MerryError extends Error with EquatableMixin {
  /// Type of error.
  final ErrorCode type;

  /// Body message of the error.
  final Map<String, dynamic> body;

  /// Constructs a constant [MerryError] instance.
  MerryError({required this.type, this.body = const {}});

  @override
  List<Object> get props => [type, body];
}
