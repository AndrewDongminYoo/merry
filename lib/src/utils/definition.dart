import 'dart:io' show Platform;

import 'package:equatable/equatable.dart';

/// Key used to define script description.
const String descriptionDefinitionKey = '(description)';

/// Key used to define scripts.
const String scriptsDefinitionKey = '(scripts)';

/// Key used to define a default script for a nested command group.
const String defaultDefinitionKey = '(default)';

/// Key used to set the working directory for a script.
const String workdirDefinitionKey = '(workdir)';

/// Key used to define aliases for a script.
const String aliasesDefinitionKey = '(aliases)';

/// Key used to define reusable variables for script interpolation.
const String variablesDefinitionKey = '(variables)';

/// Platform-specific script keys.
const String linuxDefinitionKey = '(linux)';
const String macosDefinitionKey = '(macos)';
const String windowsDefinitionKey = '(windows)';

/// Returns the metadata key for the current OS, or `null` on unsupported platforms.
String? get currentPlatformKey {
  if (Platform.isLinux) return linuxDefinitionKey;
  if (Platform.isMacOS) return macosDefinitionKey;
  if (Platform.isWindows) return windowsDefinitionKey;
  return null;
}

/// Parses a list from yaml input.
///
/// Can accept a `List` or a `String`.
List<String> _toStringList(dynamic input) {
  if (input is List) return input.map((e) => e.toString()).toList();
  if (input is String) return [input];
  throw ArgumentError.value(input, '(scripts)', 'must be a String or List');
}

/// A typical script definition.
///
/// [description] - is a short descriptive message about
/// the script which will be shown when you use `merry ls -d`.
///
/// [scripts] - is a list of commands/scripts to execute.
///
/// [workdir] - optional working directory to run the scripts in.
class Definition extends Equatable {
  @override
  List<Object?> get props => [description, scripts, workdir];

  /// Description message.
  final String? description;

  /// Scripts contained in the definition.
  final List<String> scripts;

  /// Optional working directory for script execution.
  final String? workdir;

  /// Constructs a constant [Definition] instance.
  const Definition({this.description, required this.scripts, this.workdir});

  /// Creates a [Definition] instance from a [dynamic] input.
  /// The input can be a [Map], [List] or [String].
  factory Definition.from(dynamic input) {
    if (input is Map) {
      final description = input[descriptionDefinitionKey] as String?;
      final scripts = input[scriptsDefinitionKey] as dynamic;
      final workdir = input[workdirDefinitionKey] as String?;

      return Definition(
        description: description,
        scripts: _toStringList(scripts),
        workdir: workdir,
      );
    } else {
      return Definition(scripts: _toStringList(input));
    }
  }
}
